import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/transit_models.dart';
import 'location_service.dart';

class FerryApiService {
  FerryApiService._();

  static final FerryApiService instance = FerryApiService._();

  static final Uri penangRouteUri = Uri.https(
    'service.mygeomap.gov.my',
    '/arcgis/rest/services/Basemap/1MM_BaseMap_Without_POI/MapServer/4/query',
    {
      'where': 'OBJECTID=25502',
      'outFields': 'OBJECTID,ST_NAME,ST_NM_BASE',
      'outSR': '4326',
      'returnGeometry': 'true',
      'f': 'geojson',
    },
  );

  Future<List<TransitPoint>>? _penangRouteLoad;

  Future<List<TransitPoint>> loadPenangRoute() async {
    final existing = _penangRouteLoad;
    if (existing != null) return existing;

    final request = _fetchPenangRoute();
    _penangRouteLoad = request;
    try {
      return await request;
    } catch (_) {
      _penangRouteLoad = null;
      rethrow;
    }
  }

  Future<List<TransitPoint>> _fetchPenangRoute() async {
    final response = await http
        .get(penangRouteUri)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const FormatException('Government ferry data is unavailable.');
    }

    final decoded = jsonDecode(response.body);
    return parsePenangRoute(decoded);
  }
}

List<TransitPoint> parsePenangRoute(Object? decoded) {
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid ferry data.');
  }
  final features = decoded['features'];
  if (features is! List || features.isEmpty) {
    throw const FormatException('Ferry route was not found.');
  }

  for (final feature in features) {
    if (feature is! Map<String, dynamic>) continue;
    final properties = feature['properties'];
    final name = properties is Map<String, dynamic>
        ? '${properties['ST_NAME'] ?? ''}'.toUpperCase()
        : '';
    if (!name.contains('RAJA TUN UDA') ||
        !name.contains('SULTAN ABDUL HALIM')) {
      continue;
    }

    final geometry = feature['geometry'];
    final coordinates = geometry is Map<String, dynamic>
        ? geometry['coordinates']
        : null;
    if (coordinates is! List) continue;

    final points = <TransitPoint>[];
    for (final coordinate in coordinates) {
      if (coordinate is! List || coordinate.length < 2) continue;
      final longitude = coordinate[0];
      final latitude = coordinate[1];
      if (latitude is! num || longitude is! num) continue;
      final lat = latitude.toDouble();
      final lon = longitude.toDouble();
      if (!lat.isFinite ||
          !lon.isFinite ||
          !LocationService.isInsideMalaysia(lat, lon)) {
        continue;
      }
      points.add(TransitPoint(latitude: lat, longitude: lon));
    }
    if (points.length >= 2) return points;
  }

  throw const FormatException('Invalid Penang ferry route.');
}
