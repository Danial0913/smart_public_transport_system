import 'transit_models.dart';

enum AccessibilityFacility {
  wheelchairAccess,
  stepFreeAccess,
  lift,
  accessibleToilet,
}

enum AccessibilityFacilityStatus { available, unavailable, unknown }

class AccessibilityPreferences {
  const AccessibilityPreferences({
    required this.selectedNeeds,
    required this.accessibleRoutesOnly,
    required this.workingLiftsOnly,
    required this.audioGuidance,
    required this.visualAlerts,
  });

  static const defaults = AccessibilityPreferences(
    selectedNeeds: {'Wheelchair Access', 'Step-free Route'},
    accessibleRoutesOnly: true,
    workingLiftsOnly: true,
    audioGuidance: false,
    visualAlerts: true,
  );

  final Set<String> selectedNeeds;
  final bool accessibleRoutesOnly;
  final bool workingLiftsOnly;
  final bool audioGuidance;
  final bool visualAlerts;

  AccessibilityPreferences copyWith({
    Set<String>? selectedNeeds,
    bool? accessibleRoutesOnly,
    bool? workingLiftsOnly,
    bool? audioGuidance,
    bool? visualAlerts,
  }) {
    return AccessibilityPreferences(
      selectedNeeds: selectedNeeds ?? this.selectedNeeds,
      accessibleRoutesOnly: accessibleRoutesOnly ?? this.accessibleRoutesOnly,
      workingLiftsOnly: workingLiftsOnly ?? this.workingLiftsOnly,
      audioGuidance: audioGuidance ?? this.audioGuidance,
      visualAlerts: visualAlerts ?? this.visualAlerts,
    );
  }
}

class AccessibilityObservation {
  const AccessibilityObservation({
    required this.id,
    required this.stopId,
    required this.stopName,
    required this.facility,
    required this.status,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String stopId;
  final String stopName;
  final AccessibilityFacility facility;
  final AccessibilityFacilityStatus status;
  final String note;
  final DateTime createdAt;

  AccessibilityObservation copyWith({
    String? id,
    String? stopId,
    String? stopName,
    AccessibilityFacility? facility,
    AccessibilityFacilityStatus? status,
    String? note,
    DateTime? createdAt,
  }) {
    return AccessibilityObservation(
      id: id ?? this.id,
      stopId: stopId ?? this.stopId,
      stopName: stopName ?? this.stopName,
      facility: facility ?? this.facility,
      status: status ?? this.status,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class StationAccessibility {
  const StationAccessibility({
    required this.stop,
    required this.facilities,
    required this.latestObservations,
    this.officialFacilities,
  });

  final TransitStop stop;
  final Map<AccessibilityFacility, AccessibilityFacilityStatus> facilities;
  final Map<AccessibilityFacility, AccessibilityObservation> latestObservations;
  final OfficialStationFacilities? officialFacilities;

  bool get hasVerifiedAccessibility =>
      stop.accessibilityKnown && stop.accessible;

  Iterable<AccessibilityFacility> get availableFacilities =>
      AccessibilityFacility.values.where(supports);

  bool get hasAvailableFacilities => availableFacilities.isNotEmpty;

  bool supports(AccessibilityFacility facility) {
    return facilities[facility] == AccessibilityFacilityStatus.available;
  }
}

class OfficialStationFacilities {
  const OfficialStationFacilities({
    required this.sourceName,
    required this.sourceUrl,
    required this.checkedOn,
    required this.facilities,
  });

  final String sourceName;
  final String sourceUrl;
  final String checkedOn;
  final Map<AccessibilityFacility, AccessibilityFacilityStatus> facilities;
}

class AccessibilityRegion {
  const AccessibilityRegion({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
  });

  final String name;
  final double latitude;
  final double longitude;
  final double radiusKm;
}
