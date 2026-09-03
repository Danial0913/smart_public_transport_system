import 'package:flutter/material.dart';

import '../../data/accessibility_service.dart';
import '../../data/local_storage_service.dart';
import '../../models/accessibility_models.dart';
import '../../models/transit_models.dart';
import '../../theme/app_theme.dart';
import '../journey_planner_screen.dart';
import 'accessibility_report_screen.dart';
import 'accessibility_ui.dart';

class AccessibilityStationDetailScreen extends StatefulWidget {
  const AccessibilityStationDetailScreen({super.key, required this.station});

  final StationAccessibility station;

  @override
  State<AccessibilityStationDetailScreen> createState() =>
      _AccessibilityStationDetailScreenState();
}

class _AccessibilityStationDetailScreenState
    extends State<AccessibilityStationDetailScreen> {
  final _storage = LocalStorageService.instance;
  final _service = AccessibilityService.instance;
  late StationAccessibility _station;
  List<AccessibilityObservation> _observations = [];

  @override
  void initState() {
    super.initState();
    _station = widget.station;
    _refresh();
  }

  Future<void> _refresh() async {
    final observations = await _storage.getAccessibilityObservations(
      stopId: _station.stop.id,
    );
    if (!mounted) return;
    setState(() {
      _observations = observations;
      _station = _service.profileForStop(_station.stop, observations);
    });
  }

  Future<void> _report() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AccessibilityReportScreen(
          stopId: _station.stop.id,
          stopName: _station.stop.name,
        ),
      ),
    );
    if (changed == true) await _refresh();
  }

  void _planJourney() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(title: const Text('Plan Accessible Journey')),
          body: JourneyPlannerScreen(
            initialDestination: _station.stop.name,
            initialDestinationLocation: JourneyLocation.fromStop(_station.stop),
            initialAccessibleOnly: true,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Station Accessibility')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00897B), Color(0xFF00695C)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_city,
                    color: Colors.white,
                    size: 34,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _station.stop.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _station.hasVerifiedAccessibility
                        ? 'GTFS marks this stop as wheelchair boardable.'
                        : 'No wheelchair boarding confirmation in the GTFS snapshot.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Facilities',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...AccessibilityFacility.values.map(_facilityCard),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _report,
                    icon: const Icon(Icons.rate_review_outlined),
                    label: const Text('Report Status'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _planJourney,
                    icon: const Icon(Icons.route_outlined),
                    label: const Text('Plan Journey'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              'Recent observations (${_observations.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_observations.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No local observations yet. Facility statuses marked “Not reported” are unknown, not unavailable.',
                  ),
                ),
              )
            else
              ..._observations.map(
                (observation) => Card(
                  child: ListTile(
                    leading: Icon(
                      observation.status.icon,
                      color: observation.status.colour,
                    ),
                    title: Text(
                      '${observation.facility.label}: ${observation.status.label}',
                    ),
                    subtitle: Text(
                      '${observation.note}\n${accessibilityTimeLabel(observation.createdAt)}',
                    ),
                    isThreeLine: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _facilityCard(AccessibilityFacility facility) {
    final status = _station.facilities[facility]!;
    final observation = _station.latestObservations[facility];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: status.colour.withValues(alpha: 0.12),
          child: Icon(facility.icon, color: status.colour),
        ),
        title: Text(facility.label),
        subtitle: Text(
          observation == null
              ? facility == AccessibilityFacility.wheelchairAccess ||
                        facility == AccessibilityFacility.stepFreeAccess
                    ? 'From the bundled GTFS wheelchair field'
                    : 'No verified data in the supplied feed'
              : 'Reported ${accessibilityTimeLabel(observation.createdAt)}',
        ),
        trailing: Chip(
          avatar: Icon(status.icon, size: 17, color: status.colour),
          label: Text(status.label),
        ),
      ),
    );
  }
}
