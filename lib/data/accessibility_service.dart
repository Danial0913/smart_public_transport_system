import 'dart:math' as math;

import '../models/accessibility_models.dart';
import '../models/transit_models.dart';
import 'official_accessibility_catalog.dart';
import 'transit_repository.dart';


class AccessibilityStationSearch {
  AccessibilityStationSearch({
    required List<TransitStop> stops,
    required this.profileForStop,
  }) : _stops = List.unmodifiable(stops);

  final List<TransitStop> _stops;
  final StationAccessibility Function(TransitStop) profileForStop;

  int get totalCount => _stops.length;

  List<StationAccessibility> page({required int offset, int limit = 100}) {
    RangeError.checkNotNegative(offset, 'offset');
    RangeError.checkNotNegative(limit, 'limit');
    return _stops.skip(offset).take(limit).map(profileForStop).toList();
  }
}

class AccessibilityService {
  AccessibilityService._();

  static final AccessibilityService instance = AccessibilityService._();

  final TransitRepository _repository = TransitRepository.instance;
  final _officialCatalog = OfficialAccessibilityCatalog.instance;

  static const regions = <AccessibilityRegion>[
    AccessibilityRegion(
      name: 'Penang',
      latitude: 5.4141,
      longitude: 100.3288,
      radiusKm: 70,
    ),
    AccessibilityRegion(
      name: 'Kangar',
      latitude: 6.4414,
      longitude: 100.1986,
      radiusKm: 45,
    ),
    AccessibilityRegion(
      name: 'Alor Setar',
      latitude: 6.1248,
      longitude: 100.3678,
      radiusKm: 60,
    ),
    AccessibilityRegion(
      name: 'Ipoh',
      latitude: 4.5975,
      longitude: 101.0901,
      radiusKm: 70,
    ),
    AccessibilityRegion(
      name: 'Klang Valley',
      latitude: 3.1390,
      longitude: 101.6869,
      radiusKm: 80,
    ),
    AccessibilityRegion(
      name: 'Seremban',
      latitude: 2.7297,
      longitude: 101.9381,
      radiusKm: 50,
    ),
    AccessibilityRegion(
      name: 'Melaka',
      latitude: 2.1896,
      longitude: 102.2501,
      radiusKm: 60,
    ),
    AccessibilityRegion(
      name: 'Johor Bahru',
      latitude: 1.4927,
      longitude: 103.7414,
      radiusKm: 85,
    ),
    AccessibilityRegion(
      name: 'Kota Bharu',
      latitude: 6.1254,
      longitude: 102.2381,
      radiusKm: 75,
    ),
    AccessibilityRegion(
      name: 'Kuala Terengganu',
      latitude: 5.3296,
      longitude: 103.1370,
      radiusKm: 75,
    ),
    AccessibilityRegion(
      name: 'Kuching',
      latitude: 1.5533,
      longitude: 110.3592,
      radiusKm: 80,
    ),
  ];

  Future<AccessibilityStationSearch> searchStations({
    required AccessibilityRegion region,
    required String query,
    required Set<AccessibilityFacility> requiredFacilities,
  }) async {
    await _repository.ensureDataNear(region.latitude, region.longitude);
    await _officialCatalog.load();
    StationAccessibility profile(TransitStop stop) =>
        profileForStop(stop, const []);
    final matches = <(TransitStop, int)>[];
    final normalized = query.trim().toLowerCase();
    for (final stop in _repository.stops) {
      if (_distanceKm(
            region.latitude,
            region.longitude,
            stop.latitude,
            stop.longitude,
          ) >
          region.radiusKm) {
        continue;
      }
      final station = profile(stop);
      if (!_matches(station, normalized, requiredFacilities)) {
        continue;
      }
      matches.add((stop, _score(station)));
    }
    matches.sort((a, b) {
      final score = b.$2.compareTo(a.$2);
      if (score != 0) return score;
      final name = a.$1.name.compareTo(b.$1.name);
      return name != 0 ? name : a.$1.id.compareTo(b.$1.id);
    });
    return AccessibilityStationSearch(
      stops: matches.map((entry) => entry.$1).toList(),
      profileForStop: profile,
    );
  }

  Future<List<StationAccessibility>> stationsForRegion(
    AccessibilityRegion region,
  ) async {
    await _repository.ensureDataNear(region.latitude, region.longitude);
    await _officialCatalog.load();

    final stations = _repository.stops
        .where(
          (stop) =>
              _distanceKm(
                region.latitude,
                region.longitude,
                stop.latitude,
                stop.longitude,
              ) <=
              region.radiusKm,
        )
        .map((stop) => profileForStop(stop, const []))
        .where((station) => station.hasAvailableFacilities)
        .toList();
    stations.sort((a, b) {
      final accessibility = (b.hasVerifiedAccessibility ? 1 : 0).compareTo(
        a.hasVerifiedAccessibility ? 1 : 0,
      );
      return accessibility != 0
          ? accessibility
          : a.stop.name.compareTo(b.stop.name);
    });
    return stations;
  }

  StationAccessibility profileForStop(
    TransitStop stop,
    List<AccessibilityObservation> observations,
  ) {
    final latest = <AccessibilityFacility, AccessibilityObservation>{};
    for (final observation in observations) {
      final current = latest[observation.facility];
      if (current == null || observation.createdAt.isAfter(current.createdAt)) {
        latest[observation.facility] = observation;
      }
    }
    final baseStatus = !stop.accessibilityKnown
        ? AccessibilityFacilityStatus.unknown
        : stop.accessible
        ? AccessibilityFacilityStatus.available
        : AccessibilityFacilityStatus.unavailable;
    final facilities = <AccessibilityFacility, AccessibilityFacilityStatus>{
      AccessibilityFacility.wheelchairAccess: baseStatus,
      AccessibilityFacility.stepFreeAccess: AccessibilityFacilityStatus.unknown,
      AccessibilityFacility.lift: AccessibilityFacilityStatus.unknown,
      AccessibilityFacility.accessibleToilet:
          AccessibilityFacilityStatus.unknown,
    };
    final official = _officialCatalog.forStop(stop.id);
    if (official != null) {
      facilities.addAll(official.facilities);
      if (stop.accessibilityKnown) {
        facilities[AccessibilityFacility.wheelchairAccess] = baseStatus;
      }
    }
    return StationAccessibility(
      stop: stop,
      facilities: facilities,
      latestObservations: latest,
      officialFacilities: official,
    );
  }

  List<StationAccessibility> filterStations({
    required List<StationAccessibility> stations,
    required String query,
    required Set<AccessibilityFacility> requiredFacilities,
  }) {
    final normalized = query.trim().toLowerCase();
    final filtered = stations
        .where((station) => _matches(station, normalized, requiredFacilities))
        .toList();
    filtered.sort((a, b) {
      final result = _score(b).compareTo(_score(a));
      if (result != 0) return result;
      final name = a.stop.name.compareTo(b.stop.name);
      return name != 0 ? name : a.stop.id.compareTo(b.stop.id);
    });
    return filtered;
  }

  int _score(StationAccessibility station) => station.facilities.values
      .where((status) => status == AccessibilityFacilityStatus.available)
      .length;

  bool _matches(
    StationAccessibility station,
    String normalized,
    Set<AccessibilityFacility> requiredFacilities,
  ) {
    if (!station.hasAvailableFacilities) return false;
    if (normalized.isNotEmpty &&
        !station.stop.name.toLowerCase().contains(normalized)) {
      return false;
    }
    for (final facility in requiredFacilities) {
      if (!station.supports(facility)) return false;
    }
    return true;
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
