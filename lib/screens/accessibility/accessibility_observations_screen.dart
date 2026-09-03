import 'package:flutter/material.dart';

import '../../data/local_storage_service.dart';
import '../../models/accessibility_models.dart';
import '../../theme/app_theme.dart';
import 'accessibility_report_screen.dart';
import 'accessibility_ui.dart';

class AccessibilityObservationsScreen extends StatefulWidget {
  const AccessibilityObservationsScreen({super.key});

  @override
  State<AccessibilityObservationsScreen> createState() =>
      _AccessibilityObservationsScreenState();
}

class _AccessibilityObservationsScreenState
    extends State<AccessibilityObservationsScreen> {
  final _storage = LocalStorageService.instance;
  bool _loading = true;
  List<AccessibilityObservation> _observations = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await _storage.getAccessibilityObservations();
      if (!mounted) return;
      setState(() {
        _observations = values;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load reports: $error')));
    }
  }

  Future<void> _edit(AccessibilityObservation observation) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AccessibilityReportScreen(
          stopId: observation.stopId,
          stopName: observation.stopName,
          existing: observation,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(AccessibilityObservation observation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete report?'),
        content: Text(
          'Remove your ${observation.facility.label.toLowerCase()} report for ${observation.stopName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.deleteAccessibilityObservation(observation.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('My Accessibility Reports')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _observations.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 56,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 12),
                    Text('No reports yet', style: TextStyle(fontSize: 18)),
                    SizedBox(height: 6),
                    Text(
                      'Open a station to report facility availability.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _observations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final observation = _observations[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: observation.status.colour.withValues(
                          alpha: 0.12,
                        ),
                        child: Icon(
                          observation.facility.icon,
                          color: observation.status.colour,
                        ),
                      ),
                      title: Text(observation.stopName),
                      subtitle: Text(
                        '${observation.facility.label}: ${observation.status.label}\n'
                        '${observation.note}\n${accessibilityTimeLabel(observation.createdAt)}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') _edit(observation);
                          if (value == 'delete') _delete(observation);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
