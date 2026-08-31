class TransitStop {
  const TransitStop({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.accessible,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final bool accessible;

  factory TransitStop.fromJson(Map<String, dynamic> json) {
    return TransitStop(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accessible: json['accessible'] as bool? ?? false,
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
  });

  final TransitRoute route;
  final TransitStop from;
  final TransitStop to;
  final List<TransitStop> stops;
  final int durationMinutes;
  final double fare;
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

  int get transferCount => legs.length - 1;

  String get routeSummary => legs.map((leg) => leg.route.number).join(' -> ');

  List<String> get directions {
    final result = <String>[
      'Walk $originWalkingMetres m from ${origin.name} to '
          '${legs.first.from.name}.',
    ];

    for (final leg in legs) {
      result.add(
        'Take ${leg.route.mode} ${leg.route.number} from '
        '${leg.from.name} to ${leg.to.name}.',
      );
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
  });

  final String origin;
  final String destination;
  final DateTime searchedAt;
  final double? originLatitude;
  final double? originLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;

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

  factory SavedJourney.fromOption(JourneyOption option) {
    return SavedJourney(
      id: option.id,
      origin: option.origin.name,
      destination: option.destination.name,
      routeSummary: option.routeSummary,
      departureTime: option.departureTime,
      durationMinutes: option.totalDurationMinutes,
      fare: option.totalFare,
      savedAt: DateTime.now(),
      originLatitude: option.origin.latitude,
      originLongitude: option.origin.longitude,
      destinationLatitude: option.destination.latitude,
      destinationLongitude: option.destination.longitude,
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

  FavouriteItem copyWith({String? categoryId, String? title, String? subtitle}) {
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
