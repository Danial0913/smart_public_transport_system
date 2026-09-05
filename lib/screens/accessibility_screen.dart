import 'package:flutter/material.dart';

import '../data/accessibility_service.dart';
import '../data/input_validator.dart';
import '../data/local_storage_service.dart';
import '../models/accessibility_models.dart';
import '../theme/app_theme.dart';
import 'accessibility/accessibility_station_results_screen.dart';
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
  ];

  final _storage = LocalStorageService.instance;
  final _searchController = TextEditingController();
  AccessibilityPreferences _preferences = AccessibilityPreferences.defaults;
  AccessibilityRegion _region = AccessibilityService.regions.first;
  final Set<AccessibilityFacility> _facilityFilters = {};
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
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preferences = keepPreferences
          ? _preferences
          : await _storage.getAccessibilityPreferences();
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
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

  void _applyFilters() {
    if (InputValidator.accessibilityStationSearch(_searchController.text) !=
        null) {
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AccessibilityStationResultsScreen(
          region: _region,
          query: _searchController.text,
          requiredFacilities: Set.of(_facilityFilters),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Accessibility Assistance')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _introCard(),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Card(
                child: ListTile(
                  title: const Text('Could not load accessibility preferences'),
                  subtitle: Text(_error!),
                  trailing: TextButton(
                    onPressed: _load,
                    child: const Text('Try Again'),
                  ),
                ),
              )
            else
              _preferencesCard(),
            const SizedBox(height: 18),
            _searchCard(),
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
                  'Find stops, compare officially documented facilities, and plan accessible journeys.',
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
                      });
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
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            const Text(
              'Only officially available facilities are shown. Stops must have every facility selected here. With no selection, stops must have at least one available facility.',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading || _error != null || validation != null
                    ? null
                    : _applyFilters,
                icon: const Icon(Icons.filter_list),
                label: const Text('Apply Filtering'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
