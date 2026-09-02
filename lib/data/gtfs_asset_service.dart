import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GtfsAssetService {
  GtfsAssetService._();

  static final GtfsAssetService instance = GtfsAssetService._();
  final Map<String, Future<Map<String, dynamic>>> _inFlightLoads = {};

  static const _sources = <_GtfsSource>[
    _GtfsSource('ktmb', 4.2, 101.5, 2000),
    _GtfsSource('rapid-penang', 5.41, 100.33, 70),
    _GtfsSource('rapid-kl-bus', 3.14, 101.69, 80),
    _GtfsSource('rapid-kl-feeder', 3.14, 101.69, 80),
    _GtfsSource('rapid-kl-rail', 3.14, 101.69, 80),
    _GtfsSource('mybas-kangar', 6.44, 100.20, 45),
    _GtfsSource('mybas-alor-setar', 6.12, 100.37, 60),
    _GtfsSource('mybas-kota-bharu', 6.13, 102.24, 75),
    _GtfsSource('mybas-kuala-terengganu', 5.33, 103.14, 75),
    _GtfsSource('mybas-ipoh', 4.60, 101.09, 70),
    _GtfsSource('mybas-seremban-a', 2.73, 101.94, 45),
    _GtfsSource('mybas-seremban-b', 2.73, 101.94, 45),
    _GtfsSource('mybas-melaka', 2.19, 102.25, 55),
    _GtfsSource('mybas-johor', 1.49, 103.74, 80),
    _GtfsSource('mybas-kuching', 1.55, 110.35, 80),
  ];

  List<String> sourceIdsNear(
    double latitude,
    double longitude, {
    bool includeNationalRail = false,
  }) {
    return _sources
        .where((source) {
          if (source.id == 'ktmb') {
            return includeNationalRail && longitude < 105.5;
          }
          return _distanceKm(
                latitude,
                longitude,
                source.latitude,
                source.longitude,
              ) <=
              source.radiusKm;
        })
        .map((source) => source.id)
        .toList();
  }

  Future<Map<String, dynamic>> loadFeed(String sourceId) async {
    final active = _inFlightLoads[sourceId];
    if (active != null) return active;
    final load = _loadFeed(sourceId);
    _inFlightLoads[sourceId] = load;
    try {
      return await load;
    } finally {
      _inFlightLoads.remove(sourceId);
    }
  }

  Future<Map<String, dynamic>> _loadFeed(String sourceId) async {
    try {
      final text = await rootBundle.loadString('assets/data/$sourceId.json');
      final data = await compute(_decodeGtfsJson, text);
      final metadata = data['metadata'] as Map<String, dynamic>?;
      if (metadata?['sourceId'] != sourceId ||
          metadata?['parserVersion'] != 4) {
        throw const FormatException('The bundled data format is invalid.');
      }
      return data;
    } catch (error) {
      throw Exception(
        'Unable to load bundled transit data for $sourceId: $error',
      );
    }
  }

  bool isKnownSource(String sourceId) {
    return _sources.any((source) => source.id == sourceId);
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const radius = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class _GtfsSource {
  const _GtfsSource(this.id, this.latitude, this.longitude, this.radiusKm);

  final String id;
  final double latitude;
  final double longitude;
  final double radiusKm;
}

Map<String, dynamic> _decodeGtfsJson(String text) {
  return jsonDecode(text) as Map<String, dynamic>;
}
