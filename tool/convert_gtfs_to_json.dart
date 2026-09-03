import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';

const feeds = <String, String>{
  'ktmb': 'gtfs_ktmb.zip',
  'rapid-penang': 'gtfs_rapid_bus_penang.zip',
  'rapid-kl-bus': 'gtfs_rapid_bus_kl.zip',
  'rapid-kl-feeder': 'gtfs_rapid_bus_mrtfeeder.zip',
  'rapid-kl-rail': 'gtfs_rapid_rail_kl.zip',
  'mybas-kangar': 'bas_kangar.zip',
  'mybas-alor-setar': 'bas_alor_setar.zip',
  'mybas-kota-bharu': 'bas_kota_bharu.zip',
  'mybas-kuala-terengganu': 'bas_kuala_terengganu.zip',
  'mybas-ipoh': 'bas_ipoh.zip',
  'mybas-seremban-a': 'bas_seremban_a.zip',
  'mybas-seremban-b': 'bas_seremban_b.zip',
  'mybas-melaka': 'bas_melaka.zip',
  'mybas-johor': 'bas_johor.zip',
  'mybas-kuching': 'bas_kuching.zip',
};

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/convert_gtfs_to_json.dart '
      '<ZIP directory> [output directory]',
    );
    exitCode = 64;
    return;
  }
  final input = Directory(args[0]);
  final output = Directory(args.length == 2 ? args[1] : 'assets/data')
    ..createSync(recursive: true);
  if (!input.existsSync()) {
    stderr.writeln('Directory not found: ${input.path}');
    exitCode = 66;
    return;
  }

  for (final feed in feeds.entries) {
    final zip = File('${input.path}${Platform.pathSeparator}${feed.value}');
    if (!zip.existsSync()) {
      stderr.writeln('Missing ${feed.value}');
      exitCode = 66;
      continue;
    }
    stdout.writeln('Converting ${feed.value}...');
    final data = convertFeed(feed.key, feed.value, zip.readAsBytesSync());
    final file = File(
      '${output.path}${Platform.pathSeparator}${feed.key}.json',
    );
    file.writeAsStringSync(jsonEncode(data));
    stdout.writeln(
      '  ${(data['stops'] as List).length} stops, '
      '${(data['routes'] as List).length} route patterns',
    );
  }
}

Map<String, dynamic> convertFeed(
  String sourceId,
  String originalFile,
  List<int> zipBytes,
) {
  final archive = ZipDecoder().decodeBytes(zipBytes);

  String? optional(String name) {
    for (final file in archive) {
      if (file.isFile && file.name.split('/').last == name) {
        final bytes = file.readBytes();
        return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
      }
    }
    return null;
  }

  String required(String name) =>
      optional(name) ??
      (throw FormatException('$name missing in $originalFile'));

  final stops = <String, Map<String, dynamic>>{};
  final stopTable = CsvTable(required('stops.txt'));
  for (final row in stopTable.rows) {
    final id = stopTable.value(row, 'stop_id');
    final lat = double.tryParse(stopTable.value(row, 'stop_lat'));
    final lon = double.tryParse(stopTable.value(row, 'stop_lon'));
    if (id.isEmpty || lat == null || lon == null) continue;
    final wheelchairBoarding = stopTable.value(row, 'wheelchair_boarding');
    stops[id] = {
      'id': '$sourceId:$id',
      'name': stopTable.value(row, 'stop_name').trim(),
      'latitude': lat,
      'longitude': lon,
      'accessible': wheelchairBoarding != '2',
      'accessibilityKnown':
          wheelchairBoarding == '1' || wheelchairBoarding == '2',
    };
  }

  final baseRoutes = <String, Map<String, dynamic>>{};
  final routeTable = CsvTable(required('routes.txt'));
  for (final row in routeTable.rows) {
    final id = routeTable.value(row, 'route_id');
    if (id.isEmpty) continue;
    final number = routeTable.value(row, 'route_short_name').trim();
    final name = routeTable.value(row, 'route_long_name').trim();
    final description =
        '$number $name ${routeTable.value(row, 'category')} $sourceId';
    final mode = modeFor(description, routeTable.value(row, 'route_type'));
    final colour = routeTable.value(row, 'route_color').trim();
    baseRoutes[id] = {
      'id': '$sourceId:$id',
      'number': number.isEmpty ? id : number,
      'name': name.isEmpty ? (number.isEmpty ? id : number) : name,
      'mode': mode,
      'colour': RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(colour)
          ? '#$colour'
          : defaultColour(mode),
      'baseFare': mode == 'Bus' ? 1.0 : 2.0,
      'minutesPerStop': mode == 'Bus' ? 2 : 3,
      'frequencyMinutes': mode == 'Bus' ? 30 : 15,
      'accessible': true,
      'liveSupported': false,
      'sourceId': sourceId,
      'originalRouteId': id,
    };
  }

  final trips = <String, Map<String, String>>{};
  final serviceIds = <String>{};
  final tripTable = CsvTable(required('trips.txt'));
  for (final row in tripTable.rows) {
    final id = tripTable.value(row, 'trip_id');
    final routeId = tripTable.value(row, 'route_id');
    if (id.isEmpty || !baseRoutes.containsKey(routeId)) continue;
    final serviceId = tripTable.value(row, 'service_id');
    serviceIds.add(serviceId);
    trips[id] = {
      'routeId': routeId,
      'serviceId': serviceId,
      'directionId': tripTable.value(row, 'direction_id'),
      'headsign': tripTable.value(row, 'trip_headsign').trim(),
      'shapeId': tripTable.value(row, 'shape_id'),
      'accessible': tripTable.value(row, 'wheelchair_accessible'),
    };
  }

  final times = <String, List<StopTime>>{};
  final timeTable = CsvTable(required('stop_times.txt'));
  for (final row in timeTable.rows) {
    final tripId = timeTable.value(row, 'trip_id');
    final stopId = timeTable.value(row, 'stop_id');
    final sequence = int.tryParse(timeTable.value(row, 'stop_sequence'));
    if (!trips.containsKey(tripId) ||
        !stops.containsKey(stopId) ||
        sequence == null) {
      continue;
    }
    times
        .putIfAbsent(tripId, () => [])
        .add(
          StopTime(
            sequence,
            stopId,
            minutes(timeTable.value(row, 'arrival_time')),
            minutes(timeTable.value(row, 'departure_time')),
          ),
        );
  }

  final frequencies = parseFrequencies(optional('frequencies.txt'), trips.keys);
  final shapes = parseShapes(sourceId, optional('shapes.txt'));
  final groups = <String, List<String>>{};
  for (final entry in times.entries) {
    entry.value.sort((a, b) => a.sequence.compareTo(b.sequence));
    if (entry.value.length < 2) continue;
    final trip = trips[entry.key]!;
    final signature = entry.value.map((time) => time.stopId).join('\u001f');
    final key =
        '${trip['routeId']}\u001e${trip['directionId']}\u001e$signature';
    groups.putIfAbsent(key, () => []).add(entry.key);
  }

  final usedStops = <String>{};
  final routes = <Map<String, dynamic>>[];
  var pattern = 0;
  for (final group in groups.values) {
    final firstTimes = times[group.first]!;
    usedStops.addAll(firstTimes.map((time) => time.stopId));
    final routeId = trips[group.first]!['routeId']!;
    final route = baseRoutes[routeId]!;
    final firstMinute = firstTimes.first.departure ?? firstTimes.first.arrival;
    final lastMinute = firstTimes.last.arrival ?? firstTimes.last.departure;
    final durationPerStop = firstMinute == null || lastMinute == null
        ? route['minutesPerStop']
        : math.max(
            1,
            ((lastMinute - firstMinute) / (firstTimes.length - 1)).round(),
          );
    final scheduled = <Map<String, dynamic>>[];
    final routeShapes = <String, dynamic>{};
    final headways = <int>[];
    var accessible = true;
    for (final tripId in group) {
      final trip = trips[tripId]!;
      final tripTimes = times[tripId]!;
      final shapeId = trip['shapeId']!;
      final windows = frequencies[tripId] ?? const <Map<String, int>>[];
      scheduled.add({
        'id': '$sourceId:$tripId',
        'serviceId': '$sourceId:${trip['serviceId']}',
        'headsign': trip['headsign'],
        'directionId': trip['directionId'],
        'shapeId': shapeId.isEmpty ? null : '$sourceId:$shapeId',
        'arrivalMinutes': tripTimes.map((time) => time.arrival).toList(),
        'departureMinutes': tripTimes.map((time) => time.departure).toList(),
        'frequencyWindows': windows,
      });
      headways.addAll(windows.map((window) => window['headwayMinutes']!));
      // GTFS value 0 or blank means "no information", not inaccessible.
      accessible = accessible && trip['accessible'] != '2';
      if (shapeId.isNotEmpty && shapes.containsKey('$sourceId:$shapeId')) {
        routeShapes['$sourceId:$shapeId'] = shapes['$sourceId:$shapeId'];
      }
    }
    headways.sort();
    final knownFrequency = headways.isEmpty
        ? null
        : headways[headways.length ~/ 2];
    pattern++;
    routes.add({
      ...route,
      'id': '${route['id']}:pattern-$pattern',
      'minutesPerStop': durationPerStop,
      'frequencyMinutes': knownFrequency ?? route['frequencyMinutes'],
      'knownFrequencyMinutes': knownFrequency,
      'knownFare': null,
      'accessible': accessible,
      'stopIds': firstTimes.map((time) => '$sourceId:${time.stopId}').toList(),
      'scheduledTrips': scheduled,
      'shapes': routeShapes,
    });
  }

  final calendars = parseCalendars(
    sourceId,
    serviceIds,
    optional('calendar.txt'),
    optional('calendar_dates.txt'),
  );
  if (sourceId == 'rapid-penang') {
    _addOfficialPenangFerryConnector(
      routes: routes,
      stops: stops,
      usedStops: usedStops,
      calendars: calendars,
    );
  }

  return {
    'metadata': {
      'sourceId': sourceId,
      'parserVersion': 4,
      'source': 'Bundled official Malaysia GTFS snapshot',
      'convertedAt': DateTime.now().toIso8601String(),
      'originalFile': originalFile,
      'fareNotice': 'Fare is unavailable unless the feed has one clear value.',
    },
    'stops': usedStops.map((id) => stops[id]!).toList(),
    'routes': routes,
    'calendars': calendars,
    'transfers': const <dynamic>[],
  };
}

void _addOfficialPenangFerryConnector({
  required List<Map<String, dynamic>> routes,
  required Map<String, Map<String, dynamic>> stops,
  required Set<String> usedStops,
  required List<Map<String, dynamic>> calendars,
}) {
  const islandStopId = '12002114'; // Terminal B Weld Quay
  const mainlandStopId = '12002322'; // (M1) Penang Sentral
  if (!stops.containsKey(islandStopId) || !stops.containsKey(mainlandStopId)) {
    return;
  }

  usedStops.addAll([islandStopId, mainlandStopId]);
  calendars.add({
    'serviceId': 'rapid-penang:penang-ferry-daily',
    'startDate': '2025-01-01',
    'endDate': null,
    'weekdays': List<bool>.filled(7, true),
    'addedDates': <String>[],
    'removedDates': <String>[],
  });

  Map<String, dynamic> ferryRoute({
    required String id,
    required String directionId,
    required String headsign,
    required List<String> stopIds,
    required List<int> times,
    required int firstDeparture,
    required int finalDeparture,
  }) {
    final shapeId = 'rapid-penang:penang-ferry-shape-$directionId';
    final firstStop = stops[stopIds.first.replaceFirst('rapid-penang:', '')]!;
    final finalStop = stops[stopIds.last.replaceFirst('rapid-penang:', '')]!;
    return {
      'id': 'rapid-penang:penang-ferry:$id',
      'number': 'Ferry',
      'name': 'Penang Ferry',
      'mode': 'Ferry',
      'colour': '#00897B',
      'baseFare': 2.0,
      'knownFare': 2.0,
      'minutesPerStop': 15,
      'frequencyMinutes': 30,
      'knownFrequencyMinutes': 30,
      'accessible': true,
      'liveSupported': false,
      'sourceId': 'rapid-penang',
      'originalRouteId': 'penang-ferry',
      'stopIds': stopIds,
      'scheduledTrips': [
        {
          'id': 'rapid-penang:penang-ferry-trip-$directionId',
          'serviceId': 'rapid-penang:penang-ferry-daily',
          'headsign': headsign,
          'directionId': directionId,
          'shapeId': shapeId,
          'arrivalMinutes': times,
          'departureMinutes': times,
          'frequencyWindows': [
            {
              'startMinutes': firstDeparture,
              // The repository treats the window end as exclusive.
              'endMinutes': finalDeparture + 1,
              'headwayMinutes': 30,
            },
          ],
        },
      ],
      'shapes': {
        shapeId: [
          {
            'latitude': firstStop['latitude'],
            'longitude': firstStop['longitude'],
          },
          {
            'latitude': finalStop['latitude'],
            'longitude': finalStop['longitude'],
          },
        ],
      },
    };
  }

  // Insert the ferry first so route discovery considers the direct channel
  // crossing before much longer mainland bus combinations.
  routes.insertAll(0, [
    ferryRoute(
      id: 'island-mainland',
      directionId: '0',
      headsign: 'Penang Sentral (Butterworth)',
      stopIds: const [
        'rapid-penang:$islandStopId',
        'rapid-penang:$mainlandStopId',
      ],
      times: const [420, 435],
      firstDeparture: 420,
      finalDeparture: 1410,
    ),
    ferryRoute(
      id: 'mainland-island',
      directionId: '1',
      headsign: 'Weld Quay (George Town)',
      stopIds: const [
        'rapid-penang:$mainlandStopId',
        'rapid-penang:$islandStopId',
      ],
      times: const [390, 405],
      firstDeparture: 390,
      finalDeparture: 1380,
    ),
  ]);
}

Map<String, List<Map<String, int>>> parseFrequencies(
  String? text,
  Iterable<String> tripIds,
) {
  if (text == null || text.trim().isEmpty) return const {};
  final knownTrips = tripIds.toSet();
  final result = <String, List<Map<String, int>>>{};
  final table = CsvTable(text);
  for (final row in table.rows) {
    final id = table.value(row, 'trip_id');
    final start = minutes(table.value(row, 'start_time'));
    final end = minutes(table.value(row, 'end_time'));
    final seconds = int.tryParse(table.value(row, 'headway_secs'));
    if (!knownTrips.contains(id) ||
        start == null ||
        end == null ||
        seconds == null ||
        seconds <= 0) {
      continue;
    }
    result.putIfAbsent(id, () => []).add({
      'startMinutes': start,
      'endMinutes': end,
      'headwayMinutes': math.max(1, (seconds / 60).round()),
    });
  }
  return result;
}

List<Map<String, dynamic>> parseCalendars(
  String sourceId,
  Set<String> serviceIds,
  String? calendarText,
  String? datesText,
) {
  final result = <String, Map<String, dynamic>>{};
  if (calendarText != null && calendarText.trim().isNotEmpty) {
    final table = CsvTable(calendarText);
    for (final row in table.rows) {
      final id = table.value(row, 'service_id');
      if (id.isEmpty) continue;
      result[id] = {
        'serviceId': '$sourceId:$id',
        'startDate': isoDate(table.value(row, 'start_date')),
        'endDate': isoDate(table.value(row, 'end_date')),
        'weekdays': const [
          'monday',
          'tuesday',
          'wednesday',
          'thursday',
          'friday',
          'saturday',
          'sunday',
        ].map((day) => table.value(row, day) == '1').toList(),
        'addedDates': <String>[],
        'removedDates': <String>[],
      };
    }
  }
  if (datesText != null && datesText.trim().isNotEmpty) {
    final table = CsvTable(datesText);
    for (final row in table.rows) {
      final id = table.value(row, 'service_id');
      final date = table.value(row, 'date');
      if (id.isEmpty || date.isEmpty) continue;
      final calendar = result.putIfAbsent(
        id,
        () => emptyCalendar(sourceId, id),
      );
      final key = table.value(row, 'exception_type') == '1'
          ? 'addedDates'
          : 'removedDates';
      (calendar[key] as List<String>).add(date);
    }
  }
  for (final id in serviceIds) {
    result.putIfAbsent(id, () => emptyCalendar(sourceId, id, daily: true));
  }
  return result.values.toList();
}

Map<String, dynamic> emptyCalendar(
  String sourceId,
  String id, {
  bool daily = false,
}) => {
  'serviceId': '$sourceId:$id',
  'startDate': null,
  'endDate': null,
  'weekdays': List<bool>.filled(7, daily),
  'addedDates': <String>[],
  'removedDates': <String>[],
};

Map<String, List<Map<String, double>>> parseShapes(
  String sourceId,
  String? text,
) {
  if (text == null || text.trim().isEmpty) return const {};
  final values = <String, List<(int, double, double)>>{};
  final table = CsvTable(text);
  for (final row in table.rows) {
    final id = table.value(row, 'shape_id');
    final order = int.tryParse(table.value(row, 'shape_pt_sequence'));
    final lat = double.tryParse(table.value(row, 'shape_pt_lat'));
    final lon = double.tryParse(table.value(row, 'shape_pt_lon'));
    if (id.isEmpty || order == null || lat == null || lon == null) continue;
    values.putIfAbsent(id, () => []).add((order, lat, lon));
  }
  return {
    for (final entry in values.entries)
      '$sourceId:${entry.key}': sampleShape(
        entry.value..sort((a, b) => a.$1.compareTo(b.$1)),
      ),
  };
}

List<Map<String, double>> sampleShape(List<(int, double, double)> points) {
  const maximum = 250;
  if (points.length <= maximum) {
    return points
        .map((point) => {'latitude': point.$2, 'longitude': point.$3})
        .toList();
  }
  return List.generate(maximum, (index) {
    final point = points[(index * (points.length - 1) / (maximum - 1)).round()];
    return {'latitude': point.$2, 'longitude': point.$3};
  });
}

String modeFor(String description, String routeType) {
  final text = description.toLowerCase();
  final type = int.tryParse(routeType);
  if (type == 4 ||
      (type != null && type >= 1000 && type < 1100) ||
      text.contains('ferry')) {
    return 'Ferry';
  }
  if (text.contains('monorail')) return 'Monorail';
  if (text.contains('mrt')) return 'MRT';
  if (text.contains('lrt')) return 'LRT';
  if (text.contains('ktm') || routeType == '2') return 'KTM';
  return 'Bus';
}

String defaultColour(String mode) => switch (mode) {
  'Ferry' => '#00897B',
  'KTM' => '#3949AB',
  'MRT' => '#D32F2F',
  'LRT' => '#F9A825',
  'Bus' => '#1565C0',
  _ => '#7B1FA2',
};

int? minutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  return hour == null || minute == null ? null : hour * 60 + minute;
}

String? isoDate(String value) => RegExp(r'^\d{8}$').hasMatch(value)
    ? '${value.substring(0, 4)}-${value.substring(4, 6)}-${value.substring(6, 8)}'
    : null;

class StopTime {
  const StopTime(this.sequence, this.stopId, this.arrival, this.departure);
  final int sequence;
  final String stopId;
  final int? arrival;
  final int? departure;
}

class CsvTable {
  CsvTable(this.text) : headers = csvRows(text).first;
  final String text;
  final List<String> headers;
  Iterable<List<String>> get rows => csvRows(text).skip(1);
  String value(List<String> row, String name) {
    final index = headers.indexOf(name);
    return index < 0 || index >= row.length ? '' : row[index];
  }
}

Iterable<List<String>> csvRows(String text) sync* {
  for (final line in text.split('\n')) {
    if (line.trim().isNotEmpty) yield parseCsvLine(line.replaceAll('\r', ''));
  }
}

List<String> parseCsvLine(String line) {
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
