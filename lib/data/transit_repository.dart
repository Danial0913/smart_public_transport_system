import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../models/transit_models.dart';

class TransitRepository {
  TransitRepository._();

  static final TransitRepository instance = TransitRepository._();

  final Map<String, TransitStop> _stopsById = {};
  final List<TransitRoute> _routes = [];

  bool _loaded = false;
  Map<String, dynamic> _metadata = {};

  List<TransitStop> get stops => List.unmodifiable(_stopsById.values);
  List<TransitRoute> get routes => List.unmodifiable(_routes);
  Map<String, dynamic> get metadata => Map.unmodifiable(_metadata);

  Future<void> load() async {
    if (_loaded) return;

    final jsonText = await rootBundle.loadString(
      'assets/data/penang_transit_data.json',
    );
    final data = jsonDecode(jsonText) as Map<String, dynamic>;

    _metadata = data['metadata'] as Map<String, dynamic>;

    for (final item in data['stops'] as List<dynamic>) {
      final stop = TransitStop.fromJson(item as Map<String, dynamic>);
      _stopsById[stop.id] = stop;
    }

    for (final item in data['routes'] as List<dynamic>) {
      _routes.add(TransitRoute.fromJson(item as Map<String, dynamic>));
    }

    _loaded = true;
  }

  TransitStop? findStop(String input) {
    final query = _normalise(input);
    if (query.isEmpty) return null;

    if (query == 'current location' || query == 'campus' || query == 'tarumt') {
      return _stopsById['tarumt_penang'];
    }

    for (final stop in _stopsById.values) {
      if (_normalise(stop.name) == query) return stop;
    }

    for (final stop in _stopsById.values) {
      final stopName = _normalise(stop.name);
      if (stopName.contains(query) || query.contains(stopName)) return stop;
    }

    return null;
  }

  List<TransitStop> searchStops(String query, {int limit = 6}) {
    final normalised = _normalise(query);
    final matches = _stopsById.values.where((stop) {
      return normalised.isEmpty || _normalise(stop.name).contains(normalised);
    }).toList();
    matches.sort((a, b) => a.name.compareTo(b.name));
    return matches.take(limit).toList();
  }

  TransitStop? findNearestStop(double latitude, double longitude) {
    if (_stopsById.isEmpty) return null;

    TransitStop? nearestStop;
    double? smallestDifference;

    for (final stop in _stopsById.values) {
      final latitudeDifference = stop.latitude - latitude;
      final longitudeDifference = stop.longitude - longitude;
      final totalDifference =
          latitudeDifference * latitudeDifference +
          longitudeDifference * longitudeDifference;

      if (smallestDifference == null || totalDifference < smallestDifference) {
        smallestDifference = totalDifference;
        nearestStop = stop;
      }
    }

    return nearestStop;
  }

  List<TransitRoute> searchRoutes({
    String query = '',
    String mode = 'All',
  }) {
    final normalised = _normalise(query);
    final matches = _routes.where((route) {
      final modeMatches = mode == 'All' || route.mode == mode;
      final textMatches = normalised.isEmpty ||
          _normalise(route.number).contains(normalised) ||
          _normalise(route.name).contains(normalised) ||
          route.stopIds.any(
            (stopId) => _normalise(_stopsById[stopId]!.name).contains(normalised),
          );
      return modeMatches && textMatches;
    }).toList();
    matches.sort((a, b) => a.number.compareTo(b.number));
    return matches;
  }

  List<TransitStop> stopsForRoute(TransitRoute route) {
    return route.stopIds.map((id) => _stopsById[id]!).toList();
  }

  List<JourneyOption> findJourneys({
    required JourneyLocation origin,
    required JourneyLocation destination,
    required DateTime requestedTime,
    required bool departAt,
    required Set<String> selectedModes,
    required bool accessibleOnly,
    required bool fewerTransfers,
    required int maximumWalkingMetres,
    required String preference,
  }) {
    if (_distanceBetween(
          origin.latitude,
          origin.longitude,
          destination.latitude,
          destination.longitude,
        ) <
        20) {
      return [];
    }

    final originStops = _nearbyStops(origin, maximumWalkingMetres);
    final destinationStops = _nearbyStops(destination, maximumWalkingMetres);
    if (originStops.isEmpty || destinationStops.isEmpty) return [];

    final allowedRoutes = _routes.where((route) {
      return selectedModes.contains(route.mode) &&
          (!accessibleOnly || route.accessible);
    }).toList();

    final drafts = <_JourneyDraft>[];

    for (final originCandidate in originStops) {
      for (final destinationCandidate in destinationStops) {
        final boardingStop = originCandidate.stop;
        final alightingStop = destinationCandidate.stop;
        if (boardingStop.id == alightingStop.id) continue;

        for (final route in allowedRoutes) {
          final leg = _createLeg(route, boardingStop, alightingStop);
          if (leg == null) continue;
          drafts.add(
            _JourneyDraft(
              id: '${route.id}:${boardingStop.id}:${alightingStop.id}',
              legs: [leg],
              originWalkingMetres: originCandidate.distanceMetres,
              destinationWalkingMetres:
                  destinationCandidate.distanceMetres,
              walkingMetres: originCandidate.distanceMetres +
                  destinationCandidate.distanceMetres,
            ),
          );
        }

        for (final firstRoute in allowedRoutes) {
          if (!firstRoute.stopIds.contains(boardingStop.id)) continue;

          for (final secondRoute in allowedRoutes) {
            if (firstRoute.id == secondRoute.id ||
                !secondRoute.stopIds.contains(alightingStop.id)) {
              continue;
            }

            final sharedStops = firstRoute.stopIds
                .where(secondRoute.stopIds.contains)
                .where(
                  (id) => id != boardingStop.id && id != alightingStop.id,
                );

            for (final transferStopId in sharedStops) {
              final transferStop = _stopsById[transferStopId]!;
              final firstLeg = _createLeg(
                firstRoute,
                boardingStop,
                transferStop,
              );
              final secondLeg = _createLeg(
                secondRoute,
                transferStop,
                alightingStop,
              );
              if (firstLeg == null || secondLeg == null) continue;

              const transferWalkingMetres = 120;
              drafts.add(
                _JourneyDraft(
                  id: '${firstRoute.id}:${secondRoute.id}:$transferStopId:'
                      '${boardingStop.id}:${alightingStop.id}',
                  legs: [firstLeg, secondLeg],
                  originWalkingMetres: originCandidate.distanceMetres,
                  destinationWalkingMetres:
                      destinationCandidate.distanceMetres,
                  walkingMetres: originCandidate.distanceMetres +
                      destinationCandidate.distanceMetres +
                      transferWalkingMetres,
                ),
              );
            }
          }
        }
      }
    }

    final uniqueDrafts = <String, _JourneyDraft>{};
    for (final draft in drafts) {
      uniqueDrafts.putIfAbsent(draft.id, () => draft);
    }

    final options = uniqueDrafts.values
        .where((draft) => draft.walkingMetres <= maximumWalkingMetres)
        .where((draft) {
          if (!accessibleOnly) return true;
          return draft.legs.first.from.accessible &&
              draft.legs.last.to.accessible &&
              draft.legs.every(
                (leg) => leg.route.accessible &&
                    leg.stops.every((stop) => stop.accessible),
              );
        })
        .map((draft) {
          final ridingMinutes = draft.legs.fold<int>(
            0,
            (total, leg) => total + leg.durationMinutes,
          );
          final transferMinutes = math.max(0, draft.legs.length - 1) * 7;
          final walkingMinutes = math.max(2, (draft.walkingMetres / 75).ceil());
          final totalMinutes = ridingMinutes + transferMinutes + walkingMinutes;
          final totalFare = draft.legs.fold<double>(
            0,
            (total, leg) => total + leg.fare,
          );
          final departure = departAt
              ? requestedTime
              : requestedTime.subtract(Duration(minutes: totalMinutes));
          final arrival = departAt
              ? requestedTime.add(Duration(minutes: totalMinutes))
              : requestedTime;

          return JourneyOption(
            id: '${draft.id}:${departure.toIso8601String()}',
            origin: origin,
            destination: destination,
            legs: draft.legs,
            originWalkingMetres: draft.originWalkingMetres,
            destinationWalkingMetres: draft.destinationWalkingMetres,
            walkingMetres: draft.walkingMetres,
            departureTime: departure,
            arrivalTime: arrival,
            totalDurationMinutes: totalMinutes,
            totalFare: totalFare,
            accessible: draft.legs.first.from.accessible &&
                draft.legs.last.to.accessible &&
                draft.legs.every((leg) => leg.route.accessible),
          );
        })
        .toList();

    options.sort((a, b) {
      if (fewerTransfers && a.transferCount != b.transferCount) {
        return a.transferCount.compareTo(b.transferCount);
      }

      switch (preference) {
        case 'Fastest':
          final durationResult =
              a.totalDurationMinutes.compareTo(b.totalDurationMinutes);
          return durationResult != 0
              ? durationResult
              : a.totalFare.compareTo(b.totalFare);
        case 'Lowest Fare':
          final fareResult = a.totalFare.compareTo(b.totalFare);
          return fareResult != 0
              ? fareResult
              : a.totalDurationMinutes.compareTo(b.totalDurationMinutes);
        case 'Less Walking':
          final walkingResult = a.walkingMetres.compareTo(b.walkingMetres);
          return walkingResult != 0
              ? walkingResult
              : a.totalDurationMinutes.compareTo(b.totalDurationMinutes);
        default:
          return _recommendedScore(a).compareTo(_recommendedScore(b));
      }
    });

    return options.take(6).toList();
  }

  JourneyLeg? _createLeg(
    TransitRoute route,
    TransitStop from,
    TransitStop to,
  ) {
    final fromIndex = route.stopIds.indexOf(from.id);
    final toIndex = route.stopIds.indexOf(to.id);
    if (fromIndex == -1 || toIndex == -1 || fromIndex == toIndex) return null;

    final start = math.min(fromIndex, toIndex);
    final end = math.max(fromIndex, toIndex);
    var legStops = route.stopIds
        .sublist(start, end + 1)
        .map((id) => _stopsById[id]!)
        .toList();
    if (fromIndex > toIndex) {
      legStops = legStops.reversed.toList();
    }

    return JourneyLeg(
      route: route,
      from: from,
      to: to,
      stops: legStops,
      durationMinutes: math.max(1, legStops.length - 1) * route.minutesPerStop,
      fare: route.baseFare,
    );
  }

  List<_StopCandidate> _nearbyStops(
    JourneyLocation location,
    int maximumWalkingMetres,
  ) {
    final candidates = _stopsById.values.map((stop) {
      final distance = _distanceBetween(
        location.latitude,
        location.longitude,
        stop.latitude,
        stop.longitude,
      ).round();
      return _StopCandidate(stop: stop, distanceMetres: distance);
    }).where((candidate) {
      return candidate.distanceMetres <= maximumWalkingMetres;
    }).toList();

    candidates.sort(
      (a, b) => a.distanceMetres.compareTo(b.distanceMetres),
    );
    return candidates;
  }

  double _distanceBetween(
    double firstLatitude,
    double firstLongitude,
    double secondLatitude,
    double secondLongitude,
  ) {
    const earthRadiusMetres = 6371000.0;
    final firstLatitudeRadians = firstLatitude * math.pi / 180;
    final secondLatitudeRadians = secondLatitude * math.pi / 180;
    final latitudeDifference =
        (secondLatitude - firstLatitude) * math.pi / 180;
    final longitudeDifference =
        (secondLongitude - firstLongitude) * math.pi / 180;

    final value =
        math.sin(latitudeDifference / 2) *
            math.sin(latitudeDifference / 2) +
        math.cos(firstLatitudeRadians) *
            math.cos(secondLatitudeRadians) *
            math.sin(longitudeDifference / 2) *
            math.sin(longitudeDifference / 2);
    final safeValue = value.clamp(0.0, 1.0);
    final angle = 2 *
        math.atan2(
          math.sqrt(safeValue),
          math.sqrt(1 - safeValue),
        );
    return earthRadiusMetres * angle;
  }

  double _recommendedScore(JourneyOption option) {
    return option.totalDurationMinutes +
        option.totalFare * 4 +
        option.transferCount * 10 +
        option.walkingMetres / 100;
  }

  String _normalise(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _JourneyDraft {
  const _JourneyDraft({
    required this.id,
    required this.legs,
    required this.originWalkingMetres,
    required this.destinationWalkingMetres,
    required this.walkingMetres,
  });

  final String id;
  final List<JourneyLeg> legs;
  final int originWalkingMetres;
  final int destinationWalkingMetres;
  final int walkingMetres;
}

class _StopCandidate {
  const _StopCandidate({
    required this.stop,
    required this.distanceMetres,
  });

  final TransitStop stop;
  final int distanceMetres;
}
