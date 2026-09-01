import 'dart:math' as math;

import '../models/transit_models.dart';
import 'gtfs_api_service.dart';

class TransitRepository {
  TransitRepository._();

  static final TransitRepository instance = TransitRepository._();
  final GtfsApiService _api = GtfsApiService.instance;

  final Map<String, TransitStop> _stopsById = {};
  final Map<String, TransitRoute> _routesById = {};
  final Map<String, List<TransitRoute>> _routesByStopId = {};
  final Map<String, Set<String>> _routeStopIdSets = {};
  final Map<String, Set<String>> _connectedRouteIds = {};
  final Map<String, List<TransitStop>> _stopsByGridCell = {};
  final List<TransitRoute> _routes = [];
  final Set<String> _loadedSourceIds = {};

  bool _loaded = false;
  Future<void>? _loadFuture;
  Map<String, dynamic> _metadata = {};

  List<TransitStop> get stops => List.unmodifiable(_stopsById.values);
  List<TransitRoute> get routes => List.unmodifiable(_routes);
  Map<String, dynamic> get metadata => Map.unmodifiable(_metadata);

  Future<void> load() {
    if (_loaded) return Future<void>.value();

    return _loadFuture ??= _loadData();
  }

  Future<void> _loadData() async {
    _stopsById.clear();
    _routesById.clear();
    _routesByStopId.clear();
    _routeStopIdSets.clear();
    _connectedRouteIds.clear();
    _stopsByGridCell.clear();
    _routes.clear();
    _loadedSourceIds.clear();

    _loaded = true;
  }

  Future<bool> ensureDataNear(double latitude, double longitude) async {
    await load();
    return _loadSources(_api.sourceIdsNear(latitude, longitude));
  }

  Future<bool> ensureDataForJourney(
    JourneyLocation origin,
    JourneyLocation destination,
  ) async {
    await load();
    final sourceIds = <String>{
      ..._api.sourceIdsNear(origin.latitude, origin.longitude),
      ..._api.sourceIdsNear(destination.latitude, destination.longitude),
    };
    return _loadSources(sourceIds);
  }

  Future<bool> _loadSources(Iterable<String> sourceIds) async {
    var added = false;
    var attempted = 0;
    Object? lastError;

    for (final sourceId in sourceIds) {
      if (_loadedSourceIds.contains(sourceId)) continue;
      attempted++;
      try {
        final data = await _api.loadFeed(sourceId);
        await _mergeFeed(data);
        _loadedSourceIds.add(sourceId);
        added = true;
      } catch (error) {
        lastError = error;
      }
    }

    if (added) {
      await _rebuildConnections();
      _metadata = {
        'source': 'Malaysia official GTFS Static API',
        'loadedSources': _loadedSourceIds.toList(),
        'fareNotice': 'Displayed fares are estimates, not ticket quotations.',
      };
    } else if (attempted > 0 && lastError != null && _routes.isEmpty) {
      throw Exception('Unable to load official transit data: $lastError');
    }
    return added;
  }

  Future<void> _mergeFeed(Map<String, dynamic> data) async {
    final aliases = <String, String>{};
    final stopItems = data['stops'] as List<dynamic>? ?? const [];
    for (var index = 0; index < stopItems.length; index++) {
      final stop = TransitStop.fromJson(stopItems[index] as Map<String, dynamic>);
      final nearby = _findExistingStop(stop.latitude, stop.longitude, 150);
      if (nearby != null) {
        aliases[stop.id] = nearby.id;
      } else {
        aliases[stop.id] = stop.id;
        _stopsById[stop.id] = stop;
        _stopsByGridCell
            .putIfAbsent(_gridKey(stop.latitude, stop.longitude), () => [])
            .add(stop);
      }
      if (index > 0 && index % 800 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final routeItems = data['routes'] as List<dynamic>? ?? const [];
    for (var index = 0; index < routeItems.length; index++) {
      final json = Map<String, dynamic>.from(
        routeItems[index] as Map<String, dynamic>,
      );
      final originalIds = (json['stopIds'] as List<dynamic>).cast<String>();
      final stopIds = <String>[];
      for (final id in originalIds) {
        final mapped = aliases[id];
        if (mapped != null && (stopIds.isEmpty || stopIds.last != mapped)) {
          stopIds.add(mapped);
        }
      }
      if (stopIds.length < 2) continue;
      json['stopIds'] = stopIds;
      final route = TransitRoute.fromJson(json);
      if (_routesById.containsKey(route.id)) continue;
      _routes.add(route);
      _routesById[route.id] = route;
      _routeStopIdSets[route.id] = route.stopIds.toSet();
      for (final stopId in route.stopIds) {
        _routesByStopId.putIfAbsent(stopId, () => []).add(route);
      }
      if (index > 0 && index % 100 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Future<void> _rebuildConnections() async {
    _connectedRouteIds.clear();
    var processed = 0;
    for (final routesAtStop in _routesByStopId.values) {
      for (final route in routesAtStop) {
        final connections = _connectedRouteIds.putIfAbsent(route.id, () => {});
        for (final other in routesAtStop) {
          final sameService = other.number == route.number &&
              other.name == route.name;
          if (other.id != route.id && !sameService) {
            connections.add(other.id);
          }
        }
      }
      processed++;
      if (processed % 800 == 0) await Future<void>.delayed(Duration.zero);
    }
  }

  TransitStop? _findExistingStop(
    double latitude,
    double longitude,
    int maximumDistanceMetres,
  ) {
    final row = (latitude / 0.05).floor();
    final column = (longitude / 0.05).floor();
    for (var nearbyRow = row - 1; nearbyRow <= row + 1; nearbyRow++) {
      for (var nearbyColumn = column - 1;
          nearbyColumn <= column + 1;
          nearbyColumn++) {
        for (final stop in
            _stopsByGridCell['$nearbyRow:$nearbyColumn'] ?? const []) {
          if (_distanceBetween(
                latitude,
                longitude,
                stop.latitude,
                stop.longitude,
              ) <=
              maximumDistanceMetres) {
            return stop;
          }
        }
      }
    }
    return null;
  }

  TransitStop? findStop(String input) {
    final query = _normalise(input);
    if (query.isEmpty) return null;

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
    final allowedRouteIds = allowedRoutes.map((route) => route.id).toSet();

    final drafts = <_JourneyDraft>[];
    const maximumDrafts = 120;
    const maximumRouteChecks = 20000;
    var routeChecks = 0;

    candidatePairs:
    for (final originCandidate in originStops) {
      for (final destinationCandidate in destinationStops) {
        if (drafts.length >= maximumDrafts) break candidatePairs;

        final boardingStop = originCandidate.stop;
        final alightingStop = destinationCandidate.stop;
        if (boardingStop.id == alightingStop.id) continue;

        final firstRoutes = (_routesByStopId[boardingStop.id] ?? [])
            .where((route) => allowedRouteIds.contains(route.id))
            .toList();
        final finalRoutes = (_routesByStopId[alightingStop.id] ?? [])
            .where((route) => allowedRouteIds.contains(route.id))
            .toList();

        for (final route in firstRoutes) {
          if (drafts.length >= maximumDrafts) break;
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

        for (final firstRoute in firstRoutes) {
          if (drafts.length >= maximumDrafts) break;
          for (final secondRoute in finalRoutes) {
            if (drafts.length >= maximumDrafts) break;
            routeChecks++;
            if (routeChecks >= maximumRouteChecks) break candidatePairs;
            if (firstRoute.id == secondRoute.id ||
                !(_connectedRouteIds[firstRoute.id] ?? const <String>{})
                    .contains(secondRoute.id)) {
              continue;
            }

            final sharedStops = firstRoute.stopIds
                .where(_routeStopIdSets[secondRoute.id]!.contains)
                .where(
                  (id) => id != boardingStop.id && id != alightingStop.id,
                );

            for (final transferStopId in sharedStops) {
              if (drafts.length >= maximumDrafts) break;
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

        // Also allow two transfers, for example Bus -> KTM -> MRT/LRT.
        for (final firstRoute in firstRoutes) {
          if (drafts.length >= maximumDrafts) break;
          final middleRouteIds =
              _connectedRouteIds[firstRoute.id] ?? const <String>{};
          for (final middleRouteId in middleRouteIds) {
            if (drafts.length >= maximumDrafts) break;
            if (!allowedRouteIds.contains(middleRouteId)) continue;
            final middleRoute = _routesById[middleRouteId];
            if (middleRoute == null) continue;

            for (final finalRoute in finalRoutes) {
              if (drafts.length >= maximumDrafts) break;
              routeChecks++;
              if (routeChecks >= maximumRouteChecks) break candidatePairs;
              if (finalRoute.id == firstRoute.id ||
                  finalRoute.id == middleRoute.id ||
                  !(_connectedRouteIds[middleRoute.id] ?? const <String>{})
                      .contains(finalRoute.id)) {
                continue;
              }

              final firstTransferIds = firstRoute.stopIds
                  .where(_routeStopIdSets[middleRoute.id]!.contains)
                  .where(
                    (id) => id != boardingStop.id && id != alightingStop.id,
                  )
                  .take(2);
              final secondTransferIds = middleRoute.stopIds
                  .where(_routeStopIdSets[finalRoute.id]!.contains)
                  .where(
                    (id) => id != boardingStop.id && id != alightingStop.id,
                  )
                  .take(2)
                  .toList();

              for (final firstTransferId in firstTransferIds) {
                if (drafts.length >= maximumDrafts) break;
                for (final secondTransferId in secondTransferIds) {
                  if (drafts.length >= maximumDrafts) break;
                  if (firstTransferId == secondTransferId) continue;
                  final firstTransfer = _stopsById[firstTransferId]!;
                  final secondTransfer = _stopsById[secondTransferId]!;
                  final firstLeg = _createLeg(
                    firstRoute,
                    boardingStop,
                    firstTransfer,
                  );
                  final middleLeg = _createLeg(
                    middleRoute,
                    firstTransfer,
                    secondTransfer,
                  );
                  final finalLeg = _createLeg(
                    finalRoute,
                    secondTransfer,
                    alightingStop,
                  );
                  if (firstLeg == null ||
                      middleLeg == null ||
                      finalLeg == null) {
                    continue;
                  }

                  drafts.add(
                    _JourneyDraft(
                      id: '${firstRoute.id}:${middleRoute.id}:'
                          '${finalRoute.id}:$firstTransferId:'
                          '$secondTransferId:${boardingStop.id}:'
                          '${alightingStop.id}',
                      legs: [firstLeg, middleLeg, finalLeg],
                      originWalkingMetres: originCandidate.distanceMetres,
                      destinationWalkingMetres:
                          destinationCandidate.distanceMetres,
                      walkingMetres: originCandidate.distanceMetres +
                          destinationCandidate.distanceMetres +
                          240,
                    ),
                  );
                }
              }
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
    if (fromIndex == -1 || toIndex == -1 || fromIndex >= toIndex) return null;

    final legStops = route.stopIds
        .sublist(fromIndex, toIndex + 1)
        .map((id) => _stopsById[id]!)
        .toList();

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
    const gridSize = 0.05;
    final centreRow = (location.latitude / gridSize).floor();
    final centreColumn = (location.longitude / gridSize).floor();
    final cellRadius = (maximumWalkingMetres / 5000).ceil() + 1;
    final nearbyStops = <TransitStop>[];

    for (var row = centreRow - cellRadius;
        row <= centreRow + cellRadius;
        row++) {
      for (var column = centreColumn - cellRadius;
          column <= centreColumn + cellRadius;
          column++) {
        nearbyStops.addAll(
          _stopsByGridCell['$row:$column'] ?? const <TransitStop>[],
        );
      }
    }

    final candidates = nearbyStops.map((stop) {
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
    return candidates.take(6).toList();
  }

  String _gridKey(double latitude, double longitude) {
    const gridSize = 0.05;
    final row = (latitude / gridSize).floor();
    final column = (longitude / gridSize).floor();
    return '$row:$column';
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
