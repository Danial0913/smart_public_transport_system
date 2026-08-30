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
    required String originText,
    required String destinationText,
    required DateTime requestedTime,
    required bool departAt,
    required Set<String> selectedModes,
    required bool accessibleOnly,
    required bool fewerTransfers,
    required int maximumWalkingMetres,
    required String preference,
  }) {
    final origin = findStop(originText);
    final destination = findStop(destinationText);

    if (origin == null || destination == null || origin.id == destination.id) {
      return [];
    }

    final allowedRoutes = _routes.where((route) {
      return selectedModes.contains(route.mode) &&
          (!accessibleOnly || route.accessible);
    }).toList();

    final drafts = <_JourneyDraft>[];

    for (final route in allowedRoutes) {
      final leg = _createLeg(route, origin, destination);
      if (leg != null) {
        drafts.add(
          _JourneyDraft(
            id: '${route.id}:${origin.id}:${destination.id}',
            legs: [leg],
            walkingMetres: _walkingDistance(transferCount: 0),
          ),
        );
      }
    }

    for (final firstRoute in allowedRoutes) {
      if (!firstRoute.stopIds.contains(origin.id)) continue;

      for (final secondRoute in allowedRoutes) {
        if (firstRoute.id == secondRoute.id ||
            !secondRoute.stopIds.contains(destination.id)) {
          continue;
        }

        final sharedStops = firstRoute.stopIds
            .where(secondRoute.stopIds.contains)
            .where((id) => id != origin.id && id != destination.id);

        for (final transferStopId in sharedStops) {
          final transferStop = _stopsById[transferStopId]!;
          final firstLeg = _createLeg(firstRoute, origin, transferStop);
          final secondLeg = _createLeg(secondRoute, transferStop, destination);

          if (firstLeg == null || secondLeg == null) continue;

          drafts.add(
            _JourneyDraft(
              id: '${firstRoute.id}:${secondRoute.id}:$transferStopId:'
                  '${origin.id}:${destination.id}',
              legs: [firstLeg, secondLeg],
              walkingMetres: _walkingDistance(transferCount: 1),
            ),
          );
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
          return origin.accessible &&
              destination.accessible &&
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
            walkingMetres: draft.walkingMetres,
            departureTime: departure,
            arrivalTime: arrival,
            totalDurationMinutes: totalMinutes,
            totalFare: totalFare,
            accessible: origin.accessible &&
                destination.accessible &&
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
          return a.totalDurationMinutes.compareTo(b.totalDurationMinutes);
        case 'Lowest Fare':
          final fareResult = a.totalFare.compareTo(b.totalFare);
          return fareResult != 0
              ? fareResult
              : a.totalDurationMinutes.compareTo(b.totalDurationMinutes);
        case 'Less Walking':
          return a.walkingMetres.compareTo(b.walkingMetres);
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

  int _walkingDistance({required int transferCount}) {
    return 220 + transferCount * 120;
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
    required this.walkingMetres,
  });

  final String id;
  final List<JourneyLeg> legs;
  final int walkingMetres;
}
