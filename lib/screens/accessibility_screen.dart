import 'package:flutter/material.dart';

import '../data/accessibility_service.dart';
import '../data/input_validator.dart';
import '../data/local_storage_service.dart';
import '../models/accessibility_models.dart';
import '../theme/app_theme.dart';
import 'accessibility/accessibility_comparison_screen.dart';
import 'accessibility/accessibility_observations_screen.dart';
import 'accessibility/accessibility_station_detail_screen.dart';
import 'accessibility/accessibility_ui.dart';

class AccessibilityScreen extends StatefulWidget {
  const AccessibilityScreen({super.key});

  @override
  State<AccessibilityScreen> createState() => _AccessibilityScreenState();
}

class _AccessibilityScreenState extends State<AccessibilityScreen> {
  static const accessibilityTeal = Color(0xFF00897B);
  static const _needs = <(String, IconData)>[
    ('Wheelchair Access', Icons.accessible),
    ('Step-free Route', Icons.escalator_warning),
    ('Audio Guidance', Icons.record_voice_over_outlined),
    ('Visual Alerts', Icons.visibility_outlined),
  ];

  final _service = AccessibilityService.instance;
  final _storage = LocalStorageService.instance;
  final _searchController = TextEditingController();
  AccessibilityPreferences _preferences = AccessibilityPreferences.defaults;
  AccessibilityRegion _region = AccessibilityService.regions.first;
  List<StationAccessibility> _stations = [];
  final Set<String> _comparisonIds = {};
  final Set<AccessibilityFacility> _facilityFilters = {};
  bool _accessibleStationsOnly = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  Future<void> _load({bool keepPreferences = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preferences = keepPreferences
          ? _preferences
          : await _storage.getAccessibilityPreferences();
      final stations = await _service.stationsForRegion(_region);
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _stations = stations;
        _comparisonIds.removeWhere(
              (id) => !stations.any((station) => station.stop.id == id),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _updatePreferences(AccessibilityPreferences value) async {
    setState(() => _preferences = value);
    try {
      await _storage.saveAccessibilityPreferences(value);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save preferences: $error')),
      );
    }
  }

  List<StationAccessibility> get _filteredStations {
    final error = InputValidator.accessibilityStationSearch(
      _searchController.text,
    );
    if (error != null) return const [];
    return _service.filterStations(
      stations: _stations,
      query: _searchController.text,
      accessibleOnly: _accessibleStationsOnly,
      requiredFacilities: {..._facilityFilters, ..._requiredFacilities},
      workingLiftsOnly: _preferences.workingLiftsOnly,
    );
  }

  Set<AccessibilityFacility> get _requiredFacilities {
    final result = <AccessibilityFacility>{};
    if (_preferences.selectedNeeds.contains('Wheelchair Access')) {
      result.add(AccessibilityFacility.wheelchairAccess);
    }
    if (_preferences.selectedNeeds.contains('Step-free Route')) {
      result.add(AccessibilityFacility.stepFreeAccess);
    }
    if (_preferences.workingLiftsOnly) result.add(AccessibilityFacility.lift);
    return result;
  }

  void _toggleComparison(StationAccessibility station, bool selected) {
    if (selected && _comparisonIds.length == 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select exactly two stations to compare.'),
        ),
      );
      return;
    }
    setState(() {
      selected
          ? _comparisonIds.add(station.stop.id)
          : _comparisonIds.remove(station.stop.id);
    });
  }

  void _compare() {
    final selected = _stations
        .where((station) => _comparisonIds.contains(station.stop.id))
        .toList();
    if (selected.length != 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select exactly two stations to compare.'),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccessibilityComparisonScreen(
          first: selected[0],
          second: selected[1],
        ),
      ),
    );
  }

  Future<void> _openStation(StationAccessibility station) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AccessibilityStationDetailScreen(station: station),
      ),
    );
    await _load(keepPreferences: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Accessibility Assistance'),
        actions: [
          IconButton(
            tooltip: 'My reports',
            onPressed: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const AccessibilityObservationsScreen(),
                ),
              );
              await _load(keepPreferences: true);
            },
            icon: const Icon(Icons.rate_review_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(keepPreferences: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _introCard(),
            const SizedBox(height: 16),
            _preferencesCard(),
            const SizedBox(height: 18),
            _searchCard(),
            const SizedBox(height: 14),
            if (_comparisonIds.isNotEmpty) _comparisonBar(),
            if (_comparisonIds.isNotEmpty) const SizedBox(height: 12),
            _results(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _introCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [accessibilityTeal, Color(0xFF00695C)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 29,
            backgroundColor: Colors.white24,
            child: Icon(Icons.accessibility_new, color: Colors.white, size: 33),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Travel with Confidence',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Find suitable stops, compare facilities, plan accessible journeys, and share updates.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preferencesCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.tune, color: accessibilityTeal),
        title: const Text(
          'My Accessibility Needs',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Saved automatically on this device'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _needs.map((need) {
              final selected = _preferences.selectedNeeds.contains(need.$1);
              return FilterChip(
                selected: selected,
                avatar: Icon(need.$2, size: 18),
                label: Text(need.$1),
                onSelected: (value) {
                  final selectedNeeds = {..._preferences.selectedNeeds};
                  value
                      ? selectedNeeds.add(need.$1)
                      : selectedNeeds.remove(need.$1);
                  _updatePreferences(
                    _preferences.copyWith(selectedNeeds: selectedNeeds),
                  );
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _preferences.accessibleRoutesOnly,
            activeThumbColor: accessibilityTeal,
            title: const Text('Accessible routes only'),
            subtitle: const Text('Use accessible vehicles and boarding stops'),
            onChanged: (value) => _updatePreferences(
              _preferences.copyWith(accessibleRoutesOnly: value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _preferences.workingLiftsOnly,
            activeThumbColor: accessibilityTeal,
            title: const Text('Avoid reported lift outages'),
            subtitle: const Text(
              'Unknown lift status remains visible for review',
            ),
            onChanged: (value) => _updatePreferences(
              _preferences.copyWith(workingLiftsOnly: value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _preferences.audioGuidance,
            activeThumbColor: accessibilityTeal,
            title: const Text('Audio guidance'),
            onChanged: (value) =>
                _updatePreferences(_preferences.copyWith(audioGuidance: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _preferences.visualAlerts,
            activeThumbColor: accessibilityTeal,
            title: const Text('Visual alerts'),
            onChanged: (value) =>
                _updatePreferences(_preferences.copyWith(visualAlerts: value)),
          ),
        ],
      ),
    );
  }

  Widget _searchCard() {
    final validation = InputValidator.accessibilityStationSearch(
      _searchController.text,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            DropdownButtonFormField<AccessibilityRegion>(
              initialValue: _region,
              decoration: const InputDecoration(
                labelText: 'Region',
                prefixIcon: Icon(Icons.map_outlined),
                border: OutlineInputBorder(),
              ),
              items: AccessibilityService.regions
                  .map(
                    (region) => DropdownMenuItem(
                  value: region,
                  child: Text(region.name),
                ),
              )
                  .toList(),
              onChanged: _loading
                  ? null
                  : (region) {
                if (region == null) return;
                setState(() {
                  _region = region;
                  _comparisonIds.clear();
                });
                _load(keepPreferences: true);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'Search station or stop',
                hintText: 'Example: Sentral or Terminal',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                  tooltip: 'Clear search',
                  onPressed: _searchController.clear,
                  icon: const Icon(Icons.clear),
                ),
                errorText: validation,
                counterText: '',
                border: const OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _accessibleStationsOnly,
              title: const Text('Only confirmed accessible stops'),
              subtitle: const Text(
                'Most supplied feeds mark accessibility as unknown',
              ),
              onChanged: (value) =>
                  setState(() => _accessibleStationsOnly = value ?? false),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 7,
                children: AccessibilityFacility.values.map((facility) {
                  return FilterChip(
                    selected: _facilityFilters.contains(facility),
                    avatar: Icon(facility.icon, size: 17),
                    label: Text(facility.label),
                    onSelected: (selected) => setState(() {
                      selected
                          ? _facilityFilters.add(facility)
                          : _facilityFilters.remove(facility);
                    }),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _comparisonBar() {
    return Material(
      color: const Color(0xFFE0F2F1),
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        leading: const Icon(Icons.compare_arrows, color: accessibilityTeal),
        title: Text('${_comparisonIds.length} of 2 stations selected'),
        trailing: FilledButton(
          onPressed: _comparisonIds.length == 2 ? _compare : null,
          child: const Text('Compare'),
        ),
      ),
    );
  }

  Widget _results() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 36),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              TextButton(onPressed: _load, child: const Text('Try Again')),
            ],
          ),
        ),
      );
    }
    final stations = _filteredStations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${stations.length} suitable stops in ${_region.name}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          _requiredFacilities.isEmpty
              ? 'Results prioritize confirmed facility information.'
              : 'Suggestions respect your saved accessibility requirements.',
          style: const TextStyle(color: AppTheme.secondaryText),
        ),
        const SizedBox(height: 10),
        if (stations.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No matching stops. Clear a filter or include stops with unknown accessibility status.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...stations.take(60).map(_stationCard),
        if (stations.length > 60)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Showing the first 60 results. Enter a station name to narrow the list.',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
          ),
      ],
    );
  }

  Widget _stationCard(StationAccessibility station) {
    final selected = _comparisonIds.contains(station.stop.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openStation(station),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (value) =>
                    _toggleComparison(station, value ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.stop.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: AccessibilityFacility.values.map((facility) {
                        final status = station.facilities[facility]!;
                        return Tooltip(
                          message: '${facility.label}: ${status.label}',
                          child: Icon(
                            facility.icon,
                            size: 19,
                            color: status.colour,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
