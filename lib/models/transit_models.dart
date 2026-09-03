class TransitStop {
  const TransitStop({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.accessible,
    this.accessibilityKnown = false,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final bool accessible;
  final bool accessibilityKnown;

  factory TransitStop.fromJson(Map<String, dynamic> json) {
    return TransitStop(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accessible: json['accessible'] as bool? ?? false,
      accessibilityKnown: json['accessibilityKnown'] as bool? ?? false,
    );
  }
}

class JourneyLocation {
  const JourneyLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;

  factory JourneyLocation.fromStop(TransitStop stop) {
    return JourneyLocation(
      name: stop.name,
      latitude: stop.latitude,
      longitude: stop.longitude,
    );
  }
}

class TransitPoint {
  const TransitPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  factory TransitPoint.fromJson(Map<String, dynamic> json) {
    return TransitPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

class ScheduledTransitTrip {
  const ScheduledTransitTrip({
    required this.id,
    required this.serviceId,
    required this.headsign,
    required this.directionId,
    required this.shapeId,
    required this.arrivalMinutes,
    required this.departureMinutes,
    this.frequencyWindows = const [],
  });

  final String id;
  final String serviceId;
  final String headsign;
  final String directionId;
  final String? shapeId;
  final List<int?> arrivalMinutes;
  final List<int?> departureMinutes;
  final List<TransitFrequencyWindow> frequencyWindows;

  factory ScheduledTransitTrip.fromJson(Map<String, dynamic> json) {
    int? minute(dynamic value) => value == null ? null : (value as num).toInt();

    return ScheduledTransitTrip(
      id: json['id'] as String,
      serviceId: json['serviceId'] as String,
      headsign: json['headsign'] as String? ?? '',
      directionId: json['directionId'] as String? ?? '',
      shapeId: json['shapeId'] as String?,
      arrivalMinutes: (json['arrivalMinutes'] as List<dynamic>)
          .map(minute)
          .toList(),
      departureMinutes: (json['departureMinutes'] as List<dynamic>)
          .map(minute)
          .toList(),
      frequencyWindows: (json['frequencyWindows'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
            TransitFrequencyWindow.fromJson(item as Map<String, dynamic>),
      )
          .toList(),
    );
  }
}

class TransitFrequencyWindow {
  const TransitFrequencyWindow({
    required this.startMinutes,
    required this.endMinutes,
    required this.headwayMinutes,
  });

  final int startMinutes;
  final int endMinutes;
  final int headwayMinutes;

  factory TransitFrequencyWindow.fromJson(Map<String, dynamic> json) {
    return TransitFrequencyWindow(
      startMinutes: (json['startMinutes'] as num).toInt(),
      endMinutes: (json['endMinutes'] as num).toInt(),
      headwayMinutes: (json['headwayMinutes'] as num).toInt(),
    );
  }
}

class TransitServiceCalendar {
  const TransitServiceCalendar({
    required this.serviceId,
    required this.startDate,
    required this.endDate,
    required this.weekdays,
    required this.addedDates,
    required this.removedDates,
  });

  final String serviceId;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<bool> weekdays;
  final Set<String> addedDates;
  final Set<String> removedDates;

  factory TransitServiceCalendar.fromJson(Map<String, dynamic> json) {
    return TransitServiceCalendar(
      serviceId: json['serviceId'] as String,
      startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? ''),
      weekdays: (json['weekdays'] as List<dynamic>? ?? const [])
          .map((item) => item == true)
          .toList(),
      addedDates: (json['addedDates'] as List<dynamic>? ?? const [])
          .cast<String>()
          .toSet(),
      removedDates: (json['removedDates'] as List<dynamic>? ?? const [])
          .cast<String>()
          .toSet(),
    );
  }

  bool runsOn(DateTime date) {
    final key = _dateKey(date);
    if (removedDates.contains(key)) return false;
    if (addedDates.contains(key)) return true;
    if (weekdays.length != 7) return false;
    final day = DateTime(date.year, date.month, date.day);
    if (startDate != null && day.isBefore(startDate!)) return false;
    // Bundled GTFS files are snapshots and some operators publish only a
    // short date window. After that window, keep using the published weekly
    // pattern so the local planner does not suddenly lose an entire region.
    // Exact one-off exceptions remain authoritative within their date range.
    return weekdays[day.weekday - 1];
  }
}

class TransitRoute {
  const TransitRoute({
    required this.id,
    required this.number,
    required this.name,
    required this.mode,
    required this.colourHex,
    required this.baseFare,
    required this.minutesPerStop,
    required this.frequencyMinutes,
    required this.accessible,
    required this.liveSupported,
    required this.stopIds,
    this.sourceId = '',
    this.originalRouteId = '',
    this.knownFare,
    this.knownFrequencyMinutes,
    this.scheduledTrips = const [],
    this.shapes = const {},
  });

  final String id;
  final String number;
  final String name;
  final String mode;
  final String colourHex;
  final double baseFare;
  final int minutesPerStop;
  final int frequencyMinutes;
  final bool accessible;
  final bool liveSupported;
  final List<String> stopIds;
  final String sourceId;
  final String originalRouteId;
  final double? knownFare;
  final int? knownFrequencyMinutes;
  final List<ScheduledTransitTrip> scheduledTrips;
  final Map<String, List<TransitPoint>> shapes;

  bool get hasKnownFare => knownFare != null;

  factory TransitRoute.fromJson(Map<String, dynamic> json) {
    return TransitRoute(
      id: json['id'] as String,
      number: json['number'] as String,
      name: json['name'] as String,
      mode: json['mode'] as String,
      colourHex: json['colour'] as String,
      baseFare: (json['baseFare'] as num).toDouble(),
      minutesPerStop: json['minutesPerStop'] as int,
      frequencyMinutes: json['frequencyMinutes'] as int,
      accessible: json['accessible'] as bool? ?? false,
      liveSupported: json['liveSupported'] as bool? ?? false,
      stopIds: (json['stopIds'] as List<dynamic>).cast<String>(),
      sourceId: json['sourceId'] as String? ?? '',
      originalRouteId: json['originalRouteId'] as String? ?? '',
      knownFare: (json['knownFare'] as num?)?.toDouble(),
      knownFrequencyMinutes: (json['knownFrequencyMinutes'] as num?)?.toInt(),
      scheduledTrips: (json['scheduledTrips'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
            ScheduledTransitTrip.fromJson(item as Map<String, dynamic>),
      )
          .toList(),
      shapes: (json['shapes'] as Map<String, dynamic>? ?? const {}).map(
            (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .map(
                (item) => TransitPoint.fromJson(item as Map<String, dynamic>),
          )
              .toList(),
        ),
      ),
    );
  }
}

class JourneyLeg {
  const JourneyLeg({
    required this.route,
    required this.from,
    required this.to,
    required this.stops,
    required this.durationMinutes,
    required this.fare,
    this.knownFare,
    this.tripId,
    this.headsign,
    this.departureTime,
    this.arrivalTime,
    this.shapePoints = const [],
  });

  final TransitRoute route;
  final TransitStop from;
  final TransitStop to;
  final List<TransitStop> stops;
  final int durationMinutes;
  final double fare;
  final double? knownFare;
  final String? tripId;
  final String? headsign;
  final DateTime? departureTime;
  final DateTime? arrivalTime;
  final List<TransitPoint> shapePoints;
}

class JourneyOption {
  const JourneyOption({
    required this.id,
    required this.origin,
    required this.destination,
    required this.legs,
    required this.originWalkingMetres,
    required this.destinationWalkingMetres,
    required this.walkingMetres,
    required this.departureTime,
    required this.arrivalTime,
    required this.totalDurationMinutes,
    required this.totalFare,
    required this.accessible,
    this.knownTotalFare,
    this.farePartiallyKnown = false,
    this.usesOfficialSchedule = true,
  });

  final String id;
  final JourneyLocation origin;
  final JourneyLocation destination;
  final List<JourneyLeg> legs;
  final int originWalkingMetres;
  final int destinationWalkingMetres;
  final int walkingMetres;
  final DateTime departureTime;
  final DateTime arrivalTime;
  final int totalDurationMinutes;
  final double totalFare;
  final bool accessible;
  final double? knownTotalFare;
  final bool farePartiallyKnown;
  final bool usesOfficialSchedule;

  int get transferCount => legs.length - 1;

  String get routeSummary => legs.map((leg) => leg.route.number).join(' -> ');

  List<String> get modes => legs.map((leg) => leg.route.mode).toSet().toList();

  List<String> get directions {
    final result = <String>[
      'Walk $originWalkingMetres m from ${origin.name} to '
          '${legs.first.from.name}.',
    ];

    for (final leg in legs) {
      final headsignText = leg.headsign == null || leg.headsign!.trim().isEmpty
          ? ''
          : ' towards ${leg.headsign}';
      final timeText = leg.departureTime == null
          ? ''
          : ' at ${_clockTime(leg.departureTime!)}';
      result.add(
        'Board ${leg.route.mode} ${leg.route.number}$headsignText at '
            '${leg.from.name}$timeText, then leave at ${leg.to.name}.',
      );
      if (leg != legs.last) {
        result.add('Transfer at ${leg.to.name} to the next service.');
      }
    }

    result.add(
      'Walk $destinationWalkingMetres m from ${legs.last.to.name} to '
          '${destination.name}.',
    );
    return result;
  }
}

class RecentSearch {
  const RecentSearch({
    required this.origin,
    required this.destination,
    required this.searchedAt,
    this.originLatitude,
    this.originLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
    this.requestedTime,
    this.preference,
  });

  final String origin;
  final String destination;
  final DateTime searchedAt;
  final double? originLatitude;
  final double? originLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final DateTime? requestedTime;
  final String? preference;

  JourneyLocation? get originLocation {
    final latitude = originLatitude;
    final longitude = originLongitude;
    if (latitude == null || longitude == null) return null;
    return JourneyLocation(
      name: origin,
      latitude: latitude,
      longitude: longitude,
    );
  }

  JourneyLocation? get destinationLocation {
    final latitude = destinationLatitude;
    final longitude = destinationLongitude;
    if (latitude == null || longitude == null) return null;
    return JourneyLocation(
      name: destination,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class SavedJourney {
  const SavedJourney({
    required this.id,
    required this.origin,
    required this.destination,
    required this.routeSummary,
    required this.departureTime,
    required this.durationMinutes,
    required this.fare,
    required this.savedAt,
    this.originLatitude,
    this.originLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
    this.routeIds = const [],
    this.modes = const [],
    this.preference = 'Recommended',
    this.departAt = true,
    this.maximumWalkingMetres = 2000,
    this.accessibleOnly = false,
    this.fewerTransfers = false,
    this.walkingMetres = 0,
    this.transferCount = 0,
    this.knownFare,
  });

  final String id;
  final String origin;
  final String destination;
  final String routeSummary;
  final DateTime departureTime;
  final int durationMinutes;
  final double fare;
  final DateTime savedAt;
  final double? originLatitude;
  final double? originLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final List<String> routeIds;
  final List<String> modes;
  final String preference;
  final bool departAt;
  final int maximumWalkingMetres;
  final bool accessibleOnly;
  final bool fewerTransfers;
  final int walkingMetres;
  final int transferCount;
  final double? knownFare;

  JourneyLocation? get originLocation {
    final latitude = originLatitude;
    final longitude = originLongitude;
    if (latitude == null || longitude == null) return null;
    return JourneyLocation(
      name: origin,
      latitude: latitude,
      longitude: longitude,
    );
  }

  JourneyLocation? get destinationLocation {
    final latitude = destinationLatitude;
    final longitude = destinationLongitude;
    if (latitude == null || longitude == null) return null;
    return JourneyLocation(
      name: destination,
      latitude: latitude,
      longitude: longitude,
    );
  }

  factory SavedJourney.fromOption(
      JourneyOption option, {
        String? id,
        DateTime? savedAt,
        String preference = 'Recommended',
        bool departAt = true,
        int maximumWalkingMetres = 2000,
        bool accessibleOnly = false,
        bool fewerTransfers = false,
      }) {
    return SavedJourney(
      id: id ?? option.id,
      origin: option.origin.name,
      destination: option.destination.name,
      routeSummary: option.routeSummary,
      departureTime: option.departureTime,
      durationMinutes: option.totalDurationMinutes,
      fare: option.totalFare,
      savedAt: savedAt ?? DateTime.now(),
      originLatitude: option.origin.latitude,
      originLongitude: option.origin.longitude,
      destinationLatitude: option.destination.latitude,
      destinationLongitude: option.destination.longitude,
      routeIds: option.legs.map((leg) => leg.route.id).toList(),
      modes: option.modes,
      preference: preference,
      departAt: departAt,
      maximumWalkingMetres: maximumWalkingMetres,
      accessibleOnly: accessibleOnly,
      fewerTransfers: fewerTransfers,
      walkingMetres: option.walkingMetres,
      transferCount: option.transferCount,
      knownFare: option.knownTotalFare,
    );
  }

  SavedJourney copyWith({
    String? id,
    String? origin,
    String? destination,
    String? routeSummary,
    DateTime? departureTime,
    int? durationMinutes,
    double? fare,
    DateTime? savedAt,
    double? originLatitude,
    double? originLongitude,
    double? destinationLatitude,
    double? destinationLongitude,
    List<String>? routeIds,
    List<String>? modes,
    String? preference,
    bool? departAt,
    int? maximumWalkingMetres,
    bool? accessibleOnly,
    bool? fewerTransfers,
    int? walkingMetres,
    int? transferCount,
    double? knownFare,
    bool clearKnownFare = false,
  }) {
    return SavedJourney(
      id: id ?? this.id,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      routeSummary: routeSummary ?? this.routeSummary,
      departureTime: departureTime ?? this.departureTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      fare: fare ?? this.fare,
      savedAt: savedAt ?? this.savedAt,
      originLatitude: originLatitude ?? this.originLatitude,
      originLongitude: originLongitude ?? this.originLongitude,
      destinationLatitude: destinationLatitude ?? this.destinationLatitude,
      destinationLongitude: destinationLongitude ?? this.destinationLongitude,
      routeIds: routeIds ?? this.routeIds,
      modes: modes ?? this.modes,
      preference: preference ?? this.preference,
      departAt: departAt ?? this.departAt,
      maximumWalkingMetres: maximumWalkingMetres ?? this.maximumWalkingMetres,
      accessibleOnly: accessibleOnly ?? this.accessibleOnly,
      fewerTransfers: fewerTransfers ?? this.fewerTransfers,
      walkingMetres: walkingMetres ?? this.walkingMetres,
      transferCount: transferCount ?? this.transferCount,
      knownFare: clearKnownFare ? null : knownFare ?? this.knownFare,
    );
  }
}

class FavouriteCategory {
  const FavouriteCategory({
    required this.id,
    required this.name,
    required this.colourValue,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int colourValue;
  final DateTime createdAt;

  FavouriteCategory copyWith({String? name, int? colourValue}) {
    return FavouriteCategory(
      id: id,
      name: name ?? this.name,
      colourValue: colourValue ?? this.colourValue,
      createdAt: createdAt,
    );
  }
}

class FavouriteItem {
  const FavouriteItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.referenceId,
    required this.categoryId,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String subtitle;
  final String type;
  final String referenceId;
  final String categoryId;
  final DateTime createdAt;

  FavouriteItem copyWith({
    String? categoryId,
    String? title,
    String? subtitle,
  }) {
    return FavouriteItem(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      type: type,
      referenceId: referenceId,
      categoryId: categoryId ?? this.categoryId,
      createdAt: createdAt,
    );
  }
}

class ServiceUsage {
  const ServiceUsage({
    required this.routeId,
    required this.routeNumber,
    required this.routeName,
    required this.mode,
    required this.usageCount,
    required this.lastUsedAt,
  });

  final String routeId;
  final String routeNumber;
  final String routeName;
  final String mode;
  final int usageCount;
  final DateTime lastUsedAt;
}

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}$month$day';
}

String _clockTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
