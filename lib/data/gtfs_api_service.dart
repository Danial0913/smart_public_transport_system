import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_storage_service.dart';

class GtfsApiService {
  GtfsApiService._();

  static final GtfsApiService instance = GtfsApiService._();
  final LocalStorageService _storage = LocalStorageService.instance;

  static const _sources = <_GtfsSource>[
    _GtfsSource('ktmb', 'https://api.data.gov.my/gtfs-static/ktmb', 4.2, 101.5, 2000),
    _GtfsSource('rapid-penang', 'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-penang', 5.41, 100.33, 70),
    _GtfsSource('rapid-kuantan', 'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-kuantan', 3.81, 103.33, 80),
    _GtfsSource('rapid-kl-bus', 'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-kl', 3.14, 101.69, 80),
    _GtfsSource('rapid-kl-feeder', 'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-mrtfeeder', 3.14, 101.69, 80),
    _GtfsSource('rapid-kl-rail', 'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl', 3.14, 101.69, 80),
    _GtfsSource('mybas-kangar', 'https://api.data.gov.my/gtfs-static/mybas-kangar', 6.44, 100.20, 45),
    _GtfsSource('mybas-alor-setar', 'https://api.data.gov.my/gtfs-static/mybas-alor-setar', 6.12, 100.37, 60),
    _GtfsSource('mybas-kota-bharu', 'https://api.data.gov.my/gtfs-static/mybas-kota-bharu', 6.13, 102.24, 75),
    _GtfsSource('mybas-kuala-terengganu', 'https://api.data.gov.my/gtfs-static/mybas-kuala-terengganu', 5.33, 103.14, 75),
    _GtfsSource('mybas-ipoh', 'https://api.data.gov.my/gtfs-static/mybas-ipoh', 4.60, 101.09, 70),
    _GtfsSource('mybas-seremban-a', 'https://api.data.gov.my/gtfs-static/mybas-seremban-a', 2.73, 101.94, 45),
    _GtfsSource('mybas-seremban-b', 'https://api.data.gov.my/gtfs-static/mybas-seremban-b', 2.73, 101.94, 45),
    _GtfsSource('mybas-melaka', 'https://api.data.gov.my/gtfs-static/mybas-melaka', 2.19, 102.25, 55),
    _GtfsSource('mybas-johor', 'https://api.data.gov.my/gtfs-static/mybas-johor', 1.49, 103.74, 80),
    _GtfsSource('mybas-kuching', 'https://api.data.gov.my/gtfs-static/mybas-kuching', 1.55, 110.35, 80),
  ];

  List<String> sourceIdsNear(double latitude, double longitude) {
    return _sources.where((source) {
      if (source.id == 'ktmb') return longitude < 105.5;
      return _distanceKm(
            latitude,
            longitude,
            source.latitude,
            source.longitude,
          ) <=
          source.radiusKm;
    }).map((source) => source.id).toList();
  }

  Future<Map<String, dynamic>> loadFeed(String sourceId) async {
    final source = _sources.firstWhere((item) => item.id == sourceId);
    final cached = await _storage.getGtfsCache(sourceId);
    final cachedJson = cached?['json_data'] as String?;
    final updatedText = cached?['updated_at'] as String?;
    final updatedAt = updatedText == null ? null : DateTime.tryParse(updatedText);

    if (cachedJson != null &&
        updatedAt != null &&
        DateTime.now().difference(updatedAt) < const Duration(hours: 24)) {
      return compute(_decodeGtfsJson, cachedJson);
    }

    try {
      final response = await http
          .get(Uri.parse(source.url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw Exception('GTFS server returned ${response.statusCode}.');
      }

      final data = await compute(_parseGtfsZip, {
        'sourceId': source.id,
        'bytes': response.bodyBytes,
      });
      final cacheJson = await compute(_encodeGtfsJson, data);
      await _storage.saveGtfsCache(source.id, cacheJson);
      return data;
    } catch (_) {
      if (cachedJson != null) return compute(_decodeGtfsJson, cachedJson);
      rethrow;
    }
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const radius = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class _GtfsSource {
  const _GtfsSource(
    this.id,
    this.url,
    this.latitude,
    this.longitude,
    this.radiusKm,
  );

  final String id;
  final String url;
  final double latitude;
  final double longitude;
  final double radiusKm;
}

Map<String, dynamic> _decodeGtfsJson(String text) {
  return jsonDecode(text) as Map<String, dynamic>;
}

String _encodeGtfsJson(Map<String, dynamic> data) => jsonEncode(data);

Map<String, dynamic> _parseGtfsZip(Map<String, dynamic> input) {
  final sourceId = input['sourceId'] as String;
  final archive = ZipDecoder().decodeBytes(input['bytes'] as Uint8List);

  String readFile(String name) {
    for (final file in archive) {
      if (file.isFile && file.name.split('/').last == name) {
        final bytes = file.readBytes();

        if (bytes == null) {
          throw FormatException('Unable to read $name from the GTFS ZIP file.');
        }

        return utf8.decode(bytes, allowMalformed: true);
      }
    }
    throw FormatException('$name is missing from $sourceId GTFS data.');
  }

  final stopsTable = _CsvTable(readFile('stops.txt'));
  final rawStops = <String, Map<String, dynamic>>{};
  for (final row in stopsTable.rows) {
    final id = stopsTable.value(row, 'stop_id');
    final latitude = double.tryParse(stopsTable.value(row, 'stop_lat'));
    final longitude = double.tryParse(stopsTable.value(row, 'stop_lon'));
    if (id.isEmpty || latitude == null || longitude == null) continue;
    rawStops[id] = {
      'id': '$sourceId:$id',
      'name': stopsTable.value(row, 'stop_name').trim(),
      'latitude': latitude,
      'longitude': longitude,
      'accessible': stopsTable.value(row, 'wheelchair_boarding') != '2',
    };
  }

  final routesTable = _CsvTable(readFile('routes.txt'));
  final rawRoutes = <String, Map<String, dynamic>>{};
  for (final row in routesTable.rows) {
    final id = routesTable.value(row, 'route_id');
    if (id.isEmpty) continue;
    final text = '${routesTable.value(row, 'route_short_name')} '
        '${routesTable.value(row, 'route_long_name')} '
        '${routesTable.value(row, 'category')} $sourceId';
    final mode = _modeFor(text, routesTable.value(row, 'route_type'));
    final number = routesTable.value(row, 'route_short_name').trim();
    final name = routesTable.value(row, 'route_long_name').trim();
    final colour = routesTable.value(row, 'route_color').trim();
    rawRoutes[id] = {
      'id': '$sourceId:$id',
      'number': number.isEmpty ? id : number,
      'name': name.isEmpty ? (number.isEmpty ? id : number) : name,
      'mode': mode,
      'colour': _validColour(colour) ? '#$colour' : _defaultColour(mode),
      'baseFare': _baseFare(mode),
      'minutesPerStop': mode == 'Bus' ? 2 : 3,
      'frequencyMinutes': mode == 'Bus' ? 30 : 15,
      'accessible': true,
      'liveSupported': false,
    };
  }

  final tripsTable = _CsvTable(readFile('trips.txt'));
  final selectedTrips = <String, String>{};
  final patternRouteIds = <String, String>{};
  final selectedPatterns = <String>{};
  for (final row in tripsTable.rows) {
    final routeId = tripsTable.value(row, 'route_id');
    final tripId = tripsTable.value(row, 'trip_id');
    final direction = tripsTable.value(row, 'direction_id');
    final patternId = '$routeId:${direction.isEmpty ? '0' : direction}';
    if (tripId.isNotEmpty &&
        rawRoutes.containsKey(routeId) &&
        selectedPatterns.add(patternId)) {
      selectedTrips[tripId] = patternId;
      patternRouteIds[patternId] = routeId;
    }
  }

  final timesTable = _CsvTable(readFile('stop_times.txt'));
  final patterns = <String, List<(int, String, int?)>>{};
  for (final row in timesTable.rows) {
    final tripId = timesTable.value(row, 'trip_id');
    final patternId = selectedTrips[tripId];
    if (patternId == null) continue;
    final stopId = timesTable.value(row, 'stop_id');
    final sequence = int.tryParse(timesTable.value(row, 'stop_sequence'));
    if (sequence == null || !rawStops.containsKey(stopId)) continue;
    final time = _gtfsMinutes(
      timesTable.value(row, 'departure_time'),
    ) ?? _gtfsMinutes(timesTable.value(row, 'arrival_time'));
    patterns.putIfAbsent(patternId, () => []).add((sequence, stopId, time));
  }

  final routes = <Map<String, dynamic>>[];
  final usedStopIds = <String>{};
  for (final entry in patterns.entries) {
    if (entry.value.length < 2) continue;
    entry.value.sort((a, b) => a.$1.compareTo(b.$1));
    final stopIds = <String>[];
    for (final item in entry.value) {
      final prefixedId = '$sourceId:${item.$2}';
      if (stopIds.isEmpty || stopIds.last != prefixedId) stopIds.add(prefixedId);
      usedStopIds.add(item.$2);
    }
    if (stopIds.length < 2) continue;
    final routeId = patternRouteIds[entry.key]!;
    final route = rawRoutes[routeId]!;
    final firstTime = entry.value.first.$3;
    final lastTime = entry.value.last.$3;
    final minutesPerStop = firstTime == null || lastTime == null
        ? route['minutesPerStop']
        : math
            .max(
              1,
              ((lastTime - firstTime) / (stopIds.length - 1)).round(),
            )
            .toInt();
    routes.add({
      ...route,
      'id': '${route['id']}:${entry.key.split(':').last}',
      'minutesPerStop': minutesPerStop,
      'stopIds': stopIds,
    });
  }

  return {
    'metadata': {
      'sourceId': sourceId,
      'source': 'Malaysia official GTFS Static API',
      'updatedAt': DateTime.now().toIso8601String(),
      'fareNotice': 'Fares are prototype estimates because GTFS fare data is not consistently available.',
    },
    'stops': usedStopIds.map((id) => rawStops[id]!).toList(),
    'routes': routes,
  };
}

String _modeFor(String description, String routeType) {
  final text = description.toLowerCase();
  final type = int.tryParse(routeType);
  if (type == 4 || (type != null && type >= 1000 && type < 1100) ||
      text.contains('ferry') || text.contains('boat')) {
    return 'Ferry';
  }
  if (text.contains('monorail')) return 'Monorail';
  if (text.contains('mrt')) return 'MRT';
  if (text.contains('lrt')) return 'LRT';
  if (text.contains('ktm') || text.contains('ktmb') || routeType == '2') {
    return 'KTM';
  }
  return 'Bus';
}

double _baseFare(String mode) {
  if (mode == 'Bus') return 1.0;
  if (mode == 'Ferry') return 2.0;
  if (mode == 'KTM') return 2.0;
  return 1.2;
}

String _defaultColour(String mode) {
  if (mode == 'Bus') return '#1565C0';
  if (mode == 'Ferry') return '#00897B';
  if (mode == 'KTM') return '#3949AB';
  if (mode == 'MRT') return '#D32F2F';
  if (mode == 'LRT') return '#F9A825';
  return '#7B1FA2';
}

bool _validColour(String value) {
  return RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(value);
}

int? _gtfsMinutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  if (hours == null || minutes == null) return null;
  return hours * 60 + minutes;
}

class _CsvTable {
  _CsvTable(this.text) : headers = _csvRows(text).first;

  final String text;
  final List<String> headers;

  Iterable<List<String>> get rows => _csvRows(text).skip(1);

  String value(List<String> row, String name) {
    final index = headers.indexOf(name);
    return index < 0 || index >= row.length ? '' : row[index];
  }
}

Iterable<List<String>> _csvRows(String text) sync* {
  for (final line in _lines(text)) {
    if (line.trim().isNotEmpty) yield _parseCsvLine(line);
  }
}

Iterable<String> _lines(String text) sync* {
  var start = 0;
  for (var index = 0; index < text.length; index++) {
    if (text.codeUnitAt(index) == 10) {
      yield text.substring(start, index).replaceAll('\r', '');
      start = index + 1;
    }
  }
  if (start < text.length) yield text.substring(start).replaceAll('\r', '');
}

List<String> _parseCsvLine(String line) {
  final values = <String>[];
  final current = StringBuffer();
  var quoted = false;
  for (var index = 0; index < line.length; index++) {
    final character = line[index];
    if (character == '"') {
      if (quoted && index + 1 < line.length && line[index + 1] == '"') {
        current.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (character == ',' && !quoted) {
      values.add(current.toString());
      current.clear();
    } else {
      current.write(character);
    }
  }
  values.add(current.toString());
  if (values.isNotEmpty) values[0] = values[0].replaceFirst('\uFEFF', '');
  return values;
}
