import 'package:flutter/material.dart';

import '../../data/input_validator.dart';
import '../../data/local_storage_service.dart';
import '../../models/accessibility_models.dart';
import '../../theme/app_theme.dart';
import 'accessibility_ui.dart';

class AccessibilityReportScreen extends StatefulWidget {
  const AccessibilityReportScreen({
    super.key,
    required this.stopId,
    required this.stopName,
    this.existing,
  });

  final String stopId;
  final String stopName;
  final AccessibilityObservation? existing;

  @override
  State<AccessibilityReportScreen> createState() =>
      _AccessibilityReportScreenState();
}

class _AccessibilityReportScreenState extends State<AccessibilityReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storage = LocalStorageService.instance;
  late final TextEditingController _noteController;
  late AccessibilityFacility _facility;
  late AccessibilityFacilityStatus _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.existing?.note ?? '');
    _facility =
        widget.existing?.facility ?? AccessibilityFacility.wheelchairAccess;
    _status = widget.existing?.status ?? AccessibilityFacilityStatus.available;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final observation = AccessibilityObservation(
      id: widget.existing?.id ?? 'accessibility-${now.microsecondsSinceEpoch}',
      stopId: widget.stopId,
      stopName: widget.stopName,
      facility: _facility,
      status: _status,
      note: _noteController.text.trim(),
      createdAt: now,
    );
    try {
      await _storage.saveAccessibilityObservation(observation);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save observation: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Report a Facility' : 'Edit Report',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.location_on_outlined),
                ),
                title: Text(widget.stopName),
                subtitle: const Text(
                  'Your report will be stored on this device.',
                ),
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<AccessibilityFacility>(
              initialValue: _facility,
              decoration: const InputDecoration(
                labelText: 'Facility',
                prefixIcon: Icon(Icons.accessible_forward),
                border: OutlineInputBorder(),
              ),
              items: AccessibilityFacility.values
                  .map(
                    (facility) => DropdownMenuItem(
                      value: facility,
                      child: Text(facility.label),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _facility = value);
                    },
            ),
            const SizedBox(height: 18),
            const Text(
              'Current status',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<AccessibilityFacilityStatus>(
              segments: const [
                ButtonSegment(
                  value: AccessibilityFacilityStatus.available,
                  label: Text('Available'),
                  icon: Icon(Icons.check_circle_outline),
                ),
                ButtonSegment(
                  value: AccessibilityFacilityStatus.unavailable,
                  label: Text('Unavailable'),
                  icon: Icon(Icons.cancel_outlined),
                ),
              ],
              selected: {_status},
              onSelectionChanged: _saving
                  ? null
                  : (values) => setState(() => _status = values.single),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _noteController,
              enabled: !_saving,
              minLines: 4,
              maxLines: 7,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observation details',
                hintText:
                    'Example: The lift beside platform 2 is out of service.',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  InputValidator.accessibilityObservation(value ?? ''),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Report'),
            ),
          ],
        ),
      ),
    );
  }
}
