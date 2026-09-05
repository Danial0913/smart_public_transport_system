import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/accessibility_models.dart';

class OfficialAccessibilityCatalog {
  OfficialAccessibilityCatalog._();

  static final instance = OfficialAccessibilityCatalog._();
  final Map<String, OfficialStationFacilities> _stations = {};
  Future<void>? _loadFuture;

  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final text = await rootBundle.loadString(
        'assets/data/official_accessibility.json',
      );
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['schemaVersion'] != 1) {
        throw const FormatException(
          'Unsupported official facility data format',
        );
      }
      final stations = <String, OfficialStationFacilities>{};
      for (final row in data['stations'] as List) {
        final item = row as Map<String, dynamic>;
        final rawFacilities = item['facilities'] as Map<String, dynamic>;
        stations[item['stopId'] as String] = OfficialStationFacilities(
          sourceName: item['sourceName'] as String,
          sourceUrl: item['sourceUrl'] as String,
          checkedOn: item['checkedOn'] as String,
          facilities: Map.unmodifiable({
            for (final entry in rawFacilities.entries)
              AccessibilityFacility.values.byName(
                entry.key,
              ): AccessibilityFacilityStatus.values.byName(
                entry.value as String,
              ),
          }),
        );
      }
      _stations
        ..clear()
        ..addAll(stations);
    } catch (_) {
      _loadFuture = null;
      rethrow;
    }
  }

  OfficialStationFacilities? forStop(String stopId) => _stations[stopId];
}
