import 'dart:math' as math;

import '../models/accessibility_models.dart';
import '../models/transit_models.dart';
import 'local_storage_service.dart';
import 'transit_repository.dart';

class AccessibilityService {
  AccessibilityService._();

  static final AccessibilityService instance = AccessibilityService._();

  final TransitRepository _repository = TransitRepository.instance;
  final LocalStorageService _storage = LocalStorageService.instance;

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

  Future<List<StationAccessibility>> stationsForRegion(
    AccessibilityRegion region,
  ) async {
    await _repository.ensureDataNear(region.latitude, region.longitude);
    final observations = await _storage.getAccessibilityObservations();
    final byStop = <String, List<AccessibilityObservation>>{};
    for (final observation in observations) {
      byStop.putIfAbsent(observation.stopId, () => []).add(observation);
    }

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
        .map((stop) => profileForStop(stop, byStop[stop.id] ?? const []))
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
      AccessibilityFacility.stepFreeAccess: baseStatus,
      AccessibilityFacility.lift: AccessibilityFacilityStatus.unknown,
      AccessibilityFacility.accessibleToilet:
          AccessibilityFacilityStatus.unknown,
    };
    for (final entry in latest.entries) {
      facilities[entry.key] = entry.value.status;
    }
    return StationAccessibility(
      stop: stop,
      facilities: facilities,
      latestObservations: latest,
    );
  }

  List<StationAccessibility> filterStations({
    required List<StationAccessibility> stations,
    required String query,
    required bool accessibleOnly,
    required Set<AccessibilityFacility> requiredFacilities,
    required bool workingLiftsOnly,
  }) {
    final normalized = query.trim().toLowerCase();
    final filtered = stations.where((station) {
      if (normalized.isNotEmpty &&
          !station.stop.name.toLowerCase().contains(normalized)) {
        return false;
      }
      if (accessibleOnly && !station.hasVerifiedAccessibility) return false;
      for (final facility in requiredFacilities) {
        if (station.facilities[facility] ==
            AccessibilityFacilityStatus.unavailable) {
          return false;
        }
      }
      if (workingLiftsOnly &&
          station.facilities[AccessibilityFacility.lift] ==
              AccessibilityFacilityStatus.unavailable) {
        return false;
      }
      return true;
    }).toList();
    filtered.sort((a, b) {
      int score(StationAccessibility station) {
        return station.facilities.values
            .where((status) => status == AccessibilityFacilityStatus.available)
            .length;
      }

      final result = score(b).compareTo(score(a));
      return result != 0 ? result : a.stop.name.compareTo(b.stop.name);
    });
    return filtered;
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
