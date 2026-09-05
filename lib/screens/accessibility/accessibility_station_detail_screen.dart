import 'package:flutter/material.dart';

import '../../data/accessibility_service.dart';
import '../../data/official_accessibility_catalog.dart';
import '../../models/accessibility_models.dart';
import '../../models/transit_models.dart';
import '../../theme/app_theme.dart';
import '../journey_planner_screen.dart';
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
  final _service = AccessibilityService.instance;
  late StationAccessibility _station;
  String? _error;

  @override
  void initState() {
    super.initState();
    _station = widget.station;
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      await OfficialAccessibilityCatalog.instance.load();
      if (!mounted) return;
      setState(() {
        _error = null;
        _station = _service.profileForStop(_station.stop, const []);
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load official facility records.');
      }
    }
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
          physics: const AlwaysScrollableScrollPhysics(),
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
                    '${_station.availableFacilities.length} officially available facilities',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Available Facilities',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._station.availableFacilities.map(_facilityCard),
            if (!_station.hasAvailableFacilities)
              const Text('No officially available facilities for this stop.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _planJourney,
              icon: const Icon(Icons.route_outlined),
              label: const Text('Plan Journey'),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              ListTile(
                title: Text(_error!),
                trailing: TextButton(
                  onPressed: _refresh,
                  child: const Text('Try Again'),
                ),
              ),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Only facilities documented as available are shown. Facility presence does not confirm current operation or a complete step-free route.',
                ),
              ),
            ),
            if (_station.officialFacilities != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Source: ${_station.officialFacilities!.sourceName}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Checked: ${_station.officialFacilities!.checkedOn}',
                      ),
                      const SizedBox(height: 6),
                      SelectableText(_station.officialFacilities!.sourceUrl),
                    ],
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: SelectableText(
                'Government transit feed: https://developer.data.gov.my/realtime-api/gtfs-static',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _facilityCard(AccessibilityFacility facility) {
    final status = _station.facilities[facility]!;
    final official = _station.officialFacilities;
    final fromGovernment =
        facility == AccessibilityFacility.wheelchairAccess &&
        _station.stop.accessibilityKnown;
    final fromOfficial = official?.facilities.containsKey(facility) ?? false;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: status.colour.withValues(alpha: 0.12),
          child: Icon(facility.icon, color: status.colour),
        ),
        title: Text(facility.label),
        subtitle: Text(
          fromGovernment
              ? 'Government GTFS wheelchair-boarding record'
              : fromOfficial
              ? '${official!.sourceName} - Checked ${official.checkedOn}'
              : 'Not confirmed by available official records',
        ),
        trailing: Chip(
          avatar: Icon(status.icon, size: 17, color: status.colour),
          label: Text(status.label),
        ),
      ),
    );
  }
}
