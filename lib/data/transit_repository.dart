import 'dart:collection';
import 'dart:math' as math;

import '../models/transit_models.dart';
import 'gtfs_asset_service.dart';

class TransitRepository {
  TransitRepository._();

  static final TransitRepository instance = TransitRepository._();
  final GtfsAssetService _assets = GtfsAssetService.instance;

  final Map<String, TransitStop> _stopsById = {};
  final Map<String, TransitRoute> _routesById = {};
  final Map<String, List<TransitRoute>> _routesByStopId = {};
  final Map<String, Set<String>> _routeStopIdSets = {};
  final Map<String, Set<String>> _connectedRouteIds = {};
  final Map<String, TransitServiceCalendar> _calendarsById = {};
  final Map<String, List<_TransferLink>> _transfersFromStopId = {};
  final Map<String, List<_TransferPair>> _transferPairsByRoutePair = {};
  final Map<String, List<TransitStop>> _stopsByGridCell = {};
  final Map<String, List<TransitStop>> _stopsByTransferGridCell = {};
  final Map<String, List<TransitStop>> _stopsByDedupGridCell = {};
  final Map<String, double> _adultCashFaresByStopPair = {};
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
    _calendarsById.clear();
    _transfersFromStopId.clear();
    _transferPairsByRoutePair.clear();
    _stopsByGridCell.clear();
    _stopsByTransferGridCell.clear();
    _stopsByDedupGridCell.clear();
    _adultCashFaresByStopPair.clear();
    _routes.clear();
    _loadedSourceIds.clear();

    _loaded = true;
  }

  Future<bool> ensureDataNear(double latitude, double longitude) async {
    await load();
    return _loadSources(_assets.sourceIdsNear(latitude, longitude));
  }

  Future<bool> ensureDataForJourney(
    JourneyLocation origin,
    JourneyLocation destination, {
    Set<String> selectedModes = const {},
  }) async {
    await load();
    final includeNationalRail = selectedModes.contains('KTM');
    final sourceIds = <String>{
      ..._assets.sourceIdsNear(
        origin.latitude,
        origin.longitude,
        includeNationalRail: includeNationalRail,
      ),
      ..._assets.sourceIdsNear(
        destination.latitude,
        destination.longitude,
        includeNationalRail: includeNationalRail,
      ),
    };
    return _loadSources(sourceIds);
  }

  Future<bool> ensureDataForReference(String referenceId) async {
    await load();
    final separator = referenceId.indexOf(':');
    if (separator <= 0) return false;
    final sourceId = referenceId.substring(0, separator);
    if (!_assets.isKnownSource(sourceId)) return false;
    return _loadSources([sourceId]);
  }

  TransitStop? findStopById(String id) => _stopsById[id];

  TransitRoute? findRouteById(String id) => _routesById[id];

  Future<bool> _loadSources(Iterable<String> sourceIds) async {
    var added = false;
    var attempted = 0;
    Object? lastError;

    for (final sourceId in sourceIds) {
      if (_loadedSourceIds.contains(sourceId)) continue;
      attempted++;
      try {
        final data = await _assets.loadFeed(sourceId);
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
        'source': 'Bundled official Malaysia GTFS snapshots',
        'loadedSources': _loadedSourceIds.toList(),
        'fareNotice':
            'A fare is shown only when the official feed publishes one.',
      };
    } else if (attempted > 0 && lastError != null && _routes.isEmpty) {
      throw Exception('Unable to load official transit data: $lastError');
    }
    return added;
  }

  Future<void> _mergeFeed(Map<String, dynamic> data) async {
    final calendarItems = data['calendars'] as List<dynamic>? ?? const [];
    for (var index = 0; index < calendarItems.length; index++) {
      final item = calendarItems[index];
      final calendar = TransitServiceCalendar.fromJson(
        item as Map<String, dynamic>,
      );
      _calendarsById[calendar.serviceId] = calendar;
      if (index > 0 && index % 200 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final aliases = <String, String>{};
    final stopItems = data['stops'] as List<dynamic>? ?? const [];
    for (var index = 0; index < stopItems.length; index++) {
      final stop = TransitStop.fromJson(
        stopItems[index] as Map<String, dynamic>,
      );
      final nearby = _findExistingStop(
        stop.name,
        stop.latitude,
        stop.longitude,
        35,
      );
      if (nearby != null) {
        aliases[stop.id] = nearby.id;
      } else {
        aliases[stop.id] = stop.id;
        _stopsById[stop.id] = stop;
        _stopsByGridCell
            .putIfAbsent(_gridKey(stop.latitude, stop.longitude), () => [])
            .add(stop);
        _stopsByTransferGridCell
            .putIfAbsent(
              _transferGridKey(stop.latitude, stop.longitude),
              () => [],
            )
            .add(stop);
        _stopsByDedupGridCell
            .putIfAbsent(_dedupGridKey(stop.latitude, stop.longitude), () => [])
            .add(stop);
      }
      if (index > 0 && index % 200 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final sourceId =
        (data['metadata'] as Map<String, dynamic>?)?['sourceId'] as String? ??
        '';
    final adultCashFares =
        data['adultCashFares'] as Map<String, dynamic>? ?? const {};
    var processedFare = 0;
    for (final entry in adultCashFares.entries) {
      final ids = entry.key.split('\u001f');
      if (ids.length != 2) continue;
      final from = aliases[ids[0]];
      final to = aliases[ids[1]];
      final amount = entry.value;
      if (from == null || to == null || amount is! num) continue;
      _adultCashFaresByStopPair[_fareLookupKey(sourceId, from, to)] =
          amount.toDouble();
      processedFare++;
      if (processedFare % 1000 == 0) {
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
      // Yield in small batches. Yielding after every route caused hundreds of
      // unnecessary event-loop turns for the larger regional feeds.
      if (index > 0 && index % 12 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final transferItems = data['transfers'] as List<dynamic>? ?? const [];
    for (var index = 0; index < transferItems.length; index++) {
      final item = transferItems[index];
      final json = item as Map<String, dynamic>;
      final from = aliases[json['fromStopId'] as String];
      final to = aliases[json['toStopId'] as String];
      if (from == null || to == null || from == to) continue;
      _transfersFromStopId
          .putIfAbsent(from, () => [])
          .add(
            _TransferLink(
              toStopId: to,
              minimumMinutes: (json['minimumMinutes'] as num).toInt(),
            ),
          );
      if (index > 0 && index % 200 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Future<void> _rebuildConnections() async {
    _connectedRouteIds.clear();
    _transferPairsByRoutePair.clear();
    var processed = 0;
    for (final routesAtStop in _routesByStopId.values) {
      for (final route in routesAtStop) {
        final connections = _connectedRouteIds.putIfAbsent(route.id, () => {});
        for (final other in routesAtStop) {
          final sameService =
              other.number == route.number && other.name == route.name;
          if (other.id != route.id && !sameService) {
            connections.add(other.id);
          }
        }
      }
      processed++;
      if (processed % 200 == 0) await Future<void>.delayed(Duration.zero);
    }
    processed = 0;
    for (final entry in _transfersFromStopId.entries) {
      final fromRoutes = _routesByStopId[entry.key] ?? const <TransitRoute>[];
      for (final link in entry.value) {
        final toRoutes =
            _routesByStopId[link.toStopId] ?? const <TransitRoute>[];
        for (final route in fromRoutes) {
          final connections = _connectedRouteIds.putIfAbsent(
            route.id,
            () => {},
          );
          connections.addAll(
            toRoutes
                .where((other) => other.id != route.id)
                .map((item) => item.id),
          );
        }
      }
      processed++;
      if (processed % 200 == 0) await Future<void>.delayed(Duration.zero);
    }

    // Official feeds use different stop IDs and often slightly different
    // names for a bus stop beside a railway station. Connect nearby stops from
    // different operators so journeys such as Rapid Penang -> KTM -> MyBas or
    // Rapid KL can be discovered without requiring an explicit GTFS transfer.
    processed = 0;
    for (final stop in _stopsById.values) {
      final routesAtStop = _routesByStopId[stop.id] ?? const <TransitRoute>[];
      if (routesAtStop.isNotEmpty) {
        for (final nearbyStop in _stopsNearForTransfer(stop)) {
          if (nearbyStop.id == stop.id) continue;
          final nearbyRoutes =
              _routesByStopId[nearbyStop.id] ?? const <TransitRoute>[];
          for (final route in routesAtStop) {
            final connections = _connectedRouteIds.putIfAbsent(
              route.id,
              () => {},
            );
            connections.addAll(
              nearbyRoutes
                  .where((other) {
                    return other.id != route.id &&
                        other.sourceId != route.sourceId;
                  })
                  .map((other) => other.id),
            );
          }
        }
      }
      processed++;
      if (processed % 100 == 0) await Future<void>.delayed(Duration.zero);
    }
  }

  TransitStop? _findExistingStop(
    String name,
    double latitude,
    double longitude,
    int maximumDistanceMetres,
  ) {
    const gridSize = 0.001;
    final row = (latitude / gridSize).floor();
    final column = (longitude / gridSize).floor();
    for (var nearbyRow = row - 1; nearbyRow <= row + 1; nearbyRow++) {
      for (
        var nearbyColumn = column - 1;
        nearbyColumn <= column + 1;
        nearbyColumn++
      ) {
        for (final stop
            in _stopsByDedupGridCell['$nearbyRow:$nearbyColumn'] ?? const []) {
          if (_distanceBetween(
                latitude,
                longitude,
                stop.latitude,
                stop.longitude,
              ) <=
              maximumDistanceMetres) {
            if (_normalise(stop.name) == _normalise(name)) return stop;
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

  List<TransitRoute> searchRoutes({String query = '', String mode = 'All'}) {
    final normalised = _normalise(query);
    final matches = _routes.where((route) {
      final modeMatches = mode == 'All' || route.mode == mode;
      final textMatches =
          normalised.isEmpty ||
          _normalise(route.number).contains(normalised) ||
          _normalise(route.name).contains(normalised) ||
          route.stopIds.any(
            (stopId) =>
                _normalise(_stopsById[stopId]!.name).contains(normalised),
          );
      return modeMatches && textMatches;
    }).toList();
    matches.sort((a, b) => a.number.compareTo(b.number));
    return matches;
  }

  List<TransitStop> stopsForRoute(TransitRoute route) {
    return route.stopIds.map((id) => _stopsById[id]!).toList();
  }

  Future<List<JourneyOption>> findJourneys({
    required JourneyLocation origin,
    required JourneyLocation destination,
    required DateTime requestedTime,
    required bool departAt,
    required Set<String> selectedModes,
    required bool accessibleOnly,
    required bool fewerTransfers,
    required int maximumWalkingMetres,
    required String preference,
  }) async {
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
    final destinationRouteIds = <String>{
      for (final candidate in destinationStops)
        for (final route
            in _routesByStopId[candidate.stop.id] ?? const <TransitRoute>[])
          if (allowedRouteIds.contains(route.id)) route.id,
    };
    final regionalPathsByFirstRoute = <String, List<List<TransitRoute>>>{};

    final drafts = <_JourneyDraft>[];
    // Give every nearby origin stop a fair chance. Previously the first stop
    // (often the stop on the wrong side of the road) could fill the global
    // draft limit before the correct opposite-direction stop was inspected.
    const maximumDrafts = 192;
    const maximumDraftsPerOrigin = 12;
    const maximumRouteChecks = 20000;
    var routeChecks = 0;

    candidateOrigins:
    for (final originCandidate in originStops) {
      if (drafts.length >= maximumDrafts) break;
      final originDraftLimit = math.min(
        maximumDrafts,
        drafts.length + maximumDraftsPerOrigin,
      );
      for (final destinationCandidate in destinationStops) {
        if (drafts.length >= originDraftLimit) break;

        final boardingStop = originCandidate.stop;
        final alightingStop = destinationCandidate.stop;
        if (boardingStop.id == alightingStop.id) continue;
        final draftsBeforeThisStopPair = drafts.length;

        final firstRoutes = (_routesByStopId[boardingStop.id] ?? [])
            .where((route) => allowedRouteIds.contains(route.id))
            .toList();
        final finalRoutes = (_routesByStopId[alightingStop.id] ?? [])
            .where((route) => allowedRouteIds.contains(route.id))
            .toList();

        for (final route in firstRoutes) {
          if (drafts.length >= originDraftLimit) break;
          final leg = _createLeg(route, boardingStop, alightingStop);
          if (leg == null) continue;
          drafts.add(
            _JourneyDraft(
              id: '${route.id}:${boardingStop.id}:${alightingStop.id}',
              legs: [leg],
              originWalkingMetres: originCandidate.distanceMetres,
              destinationWalkingMetres: destinationCandidate.distanceMetres,
              walkingMetres:
                  originCandidate.distanceMetres +
                  destinationCandidate.distanceMetres,
              transferMinutes: const [],
            ),
          );
        }

        for (final firstRoute in firstRoutes) {
          if (drafts.length >= originDraftLimit) break;
          for (final secondRoute in finalRoutes) {
            if (drafts.length >= originDraftLimit) break;
            routeChecks++;
            if (routeChecks % 250 == 0) {
              await Future<void>.delayed(Duration.zero);
            }
            if (routeChecks >= maximumRouteChecks) break candidateOrigins;
            if (firstRoute.id == secondRoute.id) {
              continue;
            }

            final transferPairs = _transferPairs(firstRoute, secondRoute);
            for (final pair in transferPairs) {
              if (drafts.length >= originDraftLimit) break;
              final firstTransferStop = _stopsById[pair.fromStopId]!;
              final secondTransferStop = _stopsById[pair.toStopId]!;
              final firstLeg = _createLeg(
                firstRoute,
                boardingStop,
                firstTransferStop,
              );
              final secondLeg = _createLeg(
                secondRoute,
                secondTransferStop,
                alightingStop,
              );
              if (firstLeg == null || secondLeg == null) continue;

              drafts.add(
                _JourneyDraft(
                  id:
                      '${firstRoute.id}:${secondRoute.id}:${pair.fromStopId}:'
                      '${pair.toStopId}:'
                      '${boardingStop.id}:${alightingStop.id}',
                  legs: [firstLeg, secondLeg],
                  originWalkingMetres: originCandidate.distanceMetres,
                  destinationWalkingMetres: destinationCandidate.distanceMetres,
                  walkingMetres:
                      originCandidate.distanceMetres +
                      destinationCandidate.distanceMetres +
                      pair.walkingMetres,
                  transferMinutes: [pair.minimumMinutes],
                ),
              );
            }
          }
        }

        if (drafts.length > draftsBeforeThisStopPair) continue;

        // Search the operator graph for longer regional journeys, for example
        // local bus -> bridge bus -> KTM -> destination bus or rail.
        final finalRouteIds = finalRoutes.map((route) => route.id).toSet();
        for (final firstRoute in firstRoutes) {
          if (drafts.length >= originDraftLimit) break;
          final cachedRoutePaths = regionalPathsByFirstRoute.putIfAbsent(
            firstRoute.id,
            () => _routePaths(
              firstRoute: firstRoute,
              finalRouteIds: destinationRouteIds,
              allowedRouteIds: allowedRouteIds,
              maximumRoutes: 5,
            ),
          );
          for (final routePath in cachedRoutePaths.where(
            (path) => finalRouteIds.contains(path.last.id),
          )) {
            if (drafts.length >= originDraftLimit) break;
            routeChecks++;
            if (routeChecks % 50 == 0) {
              await Future<void>.delayed(Duration.zero);
            }
            if (routeChecks >= maximumRouteChecks) break candidateOrigins;
            drafts.addAll(
              _draftsForRoutePath(
                routes: routePath,
                boardingStop: boardingStop,
                alightingStop: alightingStop,
                originWalkingMetres: originCandidate.distanceMetres,
                destinationWalkingMetres: destinationCandidate.distanceMetres,
                maximumDrafts: math.min(4, originDraftLimit - drafts.length),
              ),
            );
          }
        }
      }
    }

    final uniqueDrafts = <String, _JourneyDraft>{};
    for (final draft in drafts) {
      uniqueDrafts.putIfAbsent(draft.id, () => draft);
    }

    final options = <JourneyOption>[];
    var processedDrafts = 0;
    for (final draft in uniqueDrafts.values) {
      if (draft.originWalkingMetres > maximumWalkingMetres ||
          draft.destinationWalkingMetres > maximumWalkingMetres) {
        continue;
      }
      if (accessibleOnly &&
          (!draft.legs.first.from.accessible ||
              !draft.legs.last.to.accessible ||
              draft.legs.any(
                (leg) =>
                    !leg.route.accessible ||
                    leg.stops.any((stop) => !stop.accessible),
              ))) {
        continue;
      }
      final option =
          _scheduleDraft(
            draft: draft,
            origin: origin,
            destination: destination,
            requestedTime: requestedTime,
            departAt: departAt,
          ) ??
          _estimateDraft(
            draft: draft,
            origin: origin,
            destination: destination,
            requestedTime: requestedTime,
            departAt: departAt,
          );
      options.add(option);
      processedDrafts++;
      if (processedDrafts % 4 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // Nearby boarding platforms can produce several cards with the same
    // visible service sequence. Show that route combination once and retain
    // the access path with the shortest total walk.
    final uniqueOptions = <String, JourneyOption>{};
    for (final option in options) {
      final key = _journeyRouteKey(option);
      final current = uniqueOptions[key];
      if (current == null || _preferForDuplicate(option, current)) {
        uniqueOptions[key] = option;
      }
    }
    final rankedOptions = uniqueOptions.values.toList();

    rankedOptions.sort((a, b) {
      if (fewerTransfers && a.transferCount != b.transferCount) {
        return a.transferCount.compareTo(b.transferCount);
      }

      switch (preference) {
        case 'Fastest':
          final durationResult = a.totalDurationMinutes.compareTo(
            b.totalDurationMinutes,
          );
          return durationResult != 0
              ? durationResult
              : a.totalFare.compareTo(b.totalFare);
        case 'Lowest Fee':
        case 'Lowest Fare': // Backwards compatibility for existing saved plans.
          if (a.knownTotalFare == null && b.knownTotalFare != null) return 1;
          if (a.knownTotalFare != null && b.knownTotalFare == null) return -1;
          final fareResult = (a.knownTotalFare ?? double.infinity).compareTo(
            b.knownTotalFare ?? double.infinity,
          );
          return fareResult != 0
              ? fareResult
              : a.totalDurationMinutes.compareTo(b.totalDurationMinutes);
        case 'Less Walking':
          final walkingResult = a.walkingMetres.compareTo(b.walkingMetres);
          return walkingResult != 0
              ? walkingResult
              : a.totalDurationMinutes.compareTo(b.totalDurationMinutes);
        default:
          return _compareRecommended(a, b);
      }
    });

    return rankedOptions.take(6).toList();
  }

  String _journeyRouteKey(JourneyOption option) {
    return option.legs
        .map(
          (leg) =>
              '${_normalise(leg.route.mode)}:${_normalise(leg.route.number)}',
        )
        .join('>');
  }

  bool _preferForDuplicate(JourneyOption candidate, JourneyOption current) {
    if (candidate.walkingMetres != current.walkingMetres) {
      return candidate.walkingMetres < current.walkingMetres;
    }
    if (candidate.totalDurationMinutes != current.totalDurationMinutes) {
      return candidate.totalDurationMinutes < current.totalDurationMinutes;
    }
    return candidate.departureTime.isBefore(current.departureTime);
  }

  List<_TransferPair> _transferPairs(
    TransitRoute fromRoute,
    TransitRoute toRoute,
  ) {
    final cacheKey = '${fromRoute.id}\u001f${toRoute.id}';
    final cached = _transferPairsByRoutePair[cacheKey];
    if (cached != null) return cached;

    final destinationStopIds = _routeStopIdSets[toRoute.id] ?? const <String>{};
    final pairs = <String, _TransferPair>{};
    for (final fromStopId in fromRoute.stopIds) {
      if (destinationStopIds.contains(fromStopId)) {
        pairs['$fromStopId:$fromStopId'] = _TransferPair(
          fromStopId: fromStopId,
          toStopId: fromStopId,
          minimumMinutes: 2,
          walkingMetres: 0,
        );
      }
      for (final link
          in _transfersFromStopId[fromStopId] ?? const <_TransferLink>[]) {
        if (!destinationStopIds.contains(link.toStopId)) continue;
        final fromStop = _stopsById[fromStopId]!;
        final toStop = _stopsById[link.toStopId]!;
        pairs['$fromStopId:${link.toStopId}'] = _TransferPair(
          fromStopId: fromStopId,
          toStopId: link.toStopId,
          minimumMinutes: link.minimumMinutes,
          walkingMetres: _distanceBetween(
            fromStop.latitude,
            fromStop.longitude,
            toStop.latitude,
            toStop.longitude,
          ).round(),
        );
      }
      final fromStop = _stopsById[fromStopId]!;
      for (final nearbyStop in _stopsNearForTransfer(fromStop)) {
        if (nearbyStop.id == fromStopId ||
            !destinationStopIds.contains(nearbyStop.id)) {
          continue;
        }
        final walkingMetres = _distanceBetween(
          fromStop.latitude,
          fromStop.longitude,
          nearbyStop.latitude,
          nearbyStop.longitude,
        ).round();
        pairs.putIfAbsent(
          '$fromStopId:${nearbyStop.id}',
          () => _TransferPair(
            fromStopId: fromStopId,
            toStopId: nearbyStop.id,
            minimumMinutes: math.max(2, (walkingMetres / 75).ceil()),
            walkingMetres: walkingMetres,
          ),
        );
      }
    }
    final result = pairs.values.take(6).toList(growable: false);
    _transferPairsByRoutePair[cacheKey] = result;
    return result;
  }

  List<List<TransitRoute>> _routePaths({
    required TransitRoute firstRoute,
    required Set<String> finalRouteIds,
    required Set<String> allowedRouteIds,
    required int maximumRoutes,
  }) {
    const maximumPaths = 24;
    const maximumExpandedPaths = 800;
    final results = <List<TransitRoute>>[];
    final queue = Queue<List<String>>()..add([firstRoute.id]);
    final bestDepthByRouteId = <String, int>{firstRoute.id: 1};
    final visitsByRouteId = <String, int>{firstRoute.id: 1};
    var expanded = 0;

    while (queue.isNotEmpty &&
        results.length < maximumPaths &&
        expanded < maximumExpandedPaths) {
      final path = queue.removeFirst();
      expanded++;
      final currentId = path.last;
      if (path.length >= 3 && finalRouteIds.contains(currentId)) {
        results.add(path.map((id) => _routesById[id]!).toList());
        continue;
      }
      if (path.length >= maximumRoutes) continue;

      final currentRoute = _routesById[currentId]!;
      final nextIds = (_connectedRouteIds[currentId] ?? const <String>{})
          .where(allowedRouteIds.contains)
          .toList();
      nextIds.sort((firstId, secondId) {
        int priority(String id) {
          final route = _routesById[id]!;
          if (finalRouteIds.contains(id)) return 0;
          if (route.mode == 'KTM') return 1;
          if (route.sourceId != currentRoute.sourceId) return 2;
          return 3;
        }

        return priority(firstId).compareTo(priority(secondId));
      });
      for (final nextId in nextIds) {
        if (path.contains(nextId)) continue;
        final nextDepth = path.length + 1;
        final bestDepth = bestDepthByRouteId[nextId];
        if (bestDepth != null && nextDepth > bestDepth + 1) continue;
        final visits = visitsByRouteId[nextId] ?? 0;
        if (visits >= 2) continue;
        bestDepthByRouteId.putIfAbsent(nextId, () => nextDepth);
        visitsByRouteId[nextId] = visits + 1;
        queue.add([...path, nextId]);
      }
    }
    return results;
  }

  List<_JourneyDraft> _draftsForRoutePath({
    required List<TransitRoute> routes,
    required TransitStop boardingStop,
    required TransitStop alightingStop,
    required int originWalkingMetres,
    required int destinationWalkingMetres,
    required int maximumDrafts,
  }) {
    if (routes.length < 2 || maximumDrafts <= 0) return const [];
    final results = <_JourneyDraft>[];
    final selectedPairs = <_TransferPair>[];

    void explore(int pairIndex) {
      if (results.length >= maximumDrafts) return;
      if (pairIndex == routes.length - 1) {
        final finalLeg = _createLeg(
          routes.last,
          _stopsById[selectedPairs.last.toStopId]!,
          alightingStop,
        );
        if (finalLeg == null) return;

        final legs = <JourneyLeg>[];
        for (var routeIndex = 0; routeIndex < routes.length - 1; routeIndex++) {
          final from = routeIndex == 0
              ? boardingStop
              : _stopsById[selectedPairs[routeIndex - 1].toStopId]!;
          final to = _stopsById[selectedPairs[routeIndex].fromStopId]!;
          final leg = _createLeg(routes[routeIndex], from, to);
          if (leg == null) return;
          legs.add(leg);
        }
        legs.add(finalLeg);

        final transferWalking = selectedPairs.fold<int>(
          0,
          (total, pair) => total + pair.walkingMetres,
        );
        final idParts = <String>[
          ...routes.map((route) => route.id),
          ...selectedPairs.expand((pair) => [pair.fromStopId, pair.toStopId]),
          boardingStop.id,
          alightingStop.id,
        ];
        results.add(
          _JourneyDraft(
            id: idParts.join(':'),
            legs: legs,
            originWalkingMetres: originWalkingMetres,
            destinationWalkingMetres: destinationWalkingMetres,
            walkingMetres:
                originWalkingMetres +
                destinationWalkingMetres +
                transferWalking,
            transferMinutes: selectedPairs
                .map((pair) => pair.minimumMinutes)
                .toList(),
          ),
        );
        return;
      }

      final currentRoute = routes[pairIndex];
      final nextRoute = routes[pairIndex + 1];
      for (final pair in _transferPairs(currentRoute, nextRoute).take(3)) {
        final from = pairIndex == 0
            ? boardingStop
            : _stopsById[selectedPairs.last.toStopId]!;
        final transferFrom = _stopsById[pair.fromStopId]!;
        if (_createLeg(currentRoute, from, transferFrom) == null) continue;
        selectedPairs.add(pair);
        explore(pairIndex + 1);
        selectedPairs.removeLast();
        if (results.length >= maximumDrafts) break;
      }
    }

    explore(0);
    return results;
  }

  JourneyOption? _scheduleDraft({
    required _JourneyDraft draft,
    required JourneyLocation origin,
    required JourneyLocation destination,
    required DateTime requestedTime,
    required bool departAt,
  }) {
    final originWalkMinutes = math.max(
      1,
      (draft.originWalkingMetres / 75).ceil(),
    );
    final destinationWalkMinutes = math.max(
      1,
      (draft.destinationWalkingMetres / 75).ceil(),
    );
    final scheduled = <JourneyLeg>[];

    if (departAt) {
      var cursor = requestedTime.add(Duration(minutes: originWalkMinutes));
      for (var index = 0; index < draft.legs.length; index++) {
        final template = draft.legs[index];
        final leg = _findScheduledLeg(template, cursor, forward: true);
        if (leg == null) return null;
        scheduled.add(leg);
        if (index < draft.transferMinutes.length) {
          cursor = leg.arrivalTime!.add(
            Duration(minutes: draft.transferMinutes[index]),
          );
        }
      }
    } else {
      var cursor = requestedTime.subtract(
        Duration(minutes: destinationWalkMinutes),
      );
      for (var index = draft.legs.length - 1; index >= 0; index--) {
        final template = draft.legs[index];
        final leg = _findScheduledLeg(template, cursor, forward: false);
        if (leg == null) return null;
        scheduled.insert(0, leg);
        if (index > 0) {
          cursor = leg.departureTime!.subtract(
            Duration(minutes: draft.transferMinutes[index - 1]),
          );
        }
      }
    }

    final departure = departAt
        ? requestedTime
        : scheduled.first.departureTime!.subtract(
            Duration(minutes: originWalkMinutes),
          );
    final arrival = scheduled.last.arrivalTime!.add(
      Duration(minutes: destinationWalkMinutes),
    );
    final knownFares = scheduled
        .map((leg) => leg.knownFare)
        .whereType<double>()
        .toList();
    final knownTotalFare = knownFares.length == scheduled.length
        ? knownFares.fold<double>(0, (total, fare) => total + fare)
        : null;
    final legacyFare = scheduled.fold<double>(
      0,
      (total, leg) => total + leg.fare,
    );

    return JourneyOption(
      id: '${draft.id}:${departure.toIso8601String()}',
      origin: origin,
      destination: destination,
      legs: scheduled,
      originWalkingMetres: draft.originWalkingMetres,
      destinationWalkingMetres: draft.destinationWalkingMetres,
      walkingMetres: draft.walkingMetres,
      departureTime: departure,
      arrivalTime: arrival,
      totalDurationMinutes: math.max(
        1,
        arrival.difference(departure).inMinutes,
      ),
      totalFare: legacyFare,
      knownTotalFare: knownTotalFare,
      farePartiallyKnown: knownFares.isNotEmpty && knownTotalFare == null,
      accessible:
          scheduled.first.from.accessible &&
          scheduled.last.to.accessible &&
          scheduled.every((leg) => leg.route.accessible),
    );
  }

  JourneyOption _estimateDraft({
    required _JourneyDraft draft,
    required JourneyLocation origin,
    required JourneyLocation destination,
    required DateTime requestedTime,
    required bool departAt,
  }) {
    final originWalkMinutes = math.max(
      1,
      (draft.originWalkingMetres / 75).ceil(),
    );
    final destinationWalkMinutes = math.max(
      1,
      (draft.destinationWalkingMetres / 75).ceil(),
    );
    final ridingMinutes = draft.legs.fold<int>(
      0,
      (total, leg) => total + leg.durationMinutes,
    );
    final transferMinutes = draft.transferMinutes.fold<int>(
      0,
      (total, minutes) => total + minutes,
    );
    final totalMinutes =
        originWalkMinutes +
        ridingMinutes +
        transferMinutes +
        destinationWalkMinutes;
    final departure = departAt
        ? requestedTime
        : requestedTime.subtract(Duration(minutes: totalMinutes));
    var cursor = departure.add(Duration(minutes: originWalkMinutes));
    final estimatedLegs = <JourneyLeg>[];
    for (var index = 0; index < draft.legs.length; index++) {
      final template = draft.legs[index];
      final legDeparture = cursor;
      final legArrival = legDeparture.add(
        Duration(minutes: template.durationMinutes),
      );
      estimatedLegs.add(
        JourneyLeg(
          route: template.route,
          from: template.from,
          to: template.to,
          stops: template.stops,
          durationMinutes: template.durationMinutes,
          fare: template.fare,
          knownFare: template.knownFare,
          departureTime: legDeparture,
          arrivalTime: legArrival,
          shapePoints: template.route.shapes.isEmpty
              ? const []
              : _shapeForLeg(
                  template.route.shapes.values.first,
                  template.from,
                  template.to,
                ),
        ),
      );
      cursor = legArrival;
      if (index < draft.transferMinutes.length) {
        cursor = cursor.add(Duration(minutes: draft.transferMinutes[index]));
      }
    }
    final knownFares = estimatedLegs
        .map((leg) => leg.knownFare)
        .whereType<double>()
        .toList();
    final knownTotalFare = knownFares.length == estimatedLegs.length
        ? knownFares.fold<double>(0, (total, fare) => total + fare)
        : null;
    return JourneyOption(
      id: '${draft.id}:estimated:${departure.toIso8601String()}',
      origin: origin,
      destination: destination,
      legs: estimatedLegs,
      originWalkingMetres: draft.originWalkingMetres,
      destinationWalkingMetres: draft.destinationWalkingMetres,
      walkingMetres: draft.walkingMetres,
      departureTime: departure,
      arrivalTime: departure.add(Duration(minutes: totalMinutes)),
      totalDurationMinutes: totalMinutes,
      totalFare: estimatedLegs.fold<double>(
        0,
        (total, leg) => total + leg.fare,
      ),
      knownTotalFare: knownTotalFare,
      farePartiallyKnown: knownFares.isNotEmpty && knownTotalFare == null,
      accessible:
          estimatedLegs.first.from.accessible &&
          estimatedLegs.last.to.accessible &&
          estimatedLegs.every((leg) => leg.route.accessible),
      usesOfficialSchedule: false,
    );
  }

  JourneyLeg? _findScheduledLeg(
    JourneyLeg template,
    DateTime boundary, {
    required bool forward,
  }) {
    final fromIndex = template.route.stopIds.indexOf(template.from.id);
    final toIndex = template.route.stopIds.indexOf(template.to.id);
    if (fromIndex < 0 || toIndex <= fromIndex) return null;

    JourneyLeg? best;
    ScheduledTransitTrip? bestTrip;
    final dayOffsets = forward
        ? [for (var value = -1; value <= 7; value++) value]
        : [for (var value = 0; value >= -7; value--) value];
    for (final dayOffset in dayOffsets) {
      final serviceDate = DateTime(
        boundary.year,
        boundary.month,
        boundary.day + dayOffset,
      );
      for (final trip in template.route.scheduledTrips) {
        if (trip.arrivalMinutes.length <= toIndex ||
            trip.departureMinutes.length <= fromIndex ||
            !_serviceRuns(trip.serviceId, serviceDate)) {
          continue;
        }
        final departureMinute =
            trip.departureMinutes[fromIndex] ?? trip.arrivalMinutes[fromIndex];
        final arrivalMinute =
            trip.arrivalMinutes[toIndex] ?? trip.departureMinutes[toIndex];
        if (departureMinute == null || arrivalMinute == null) continue;

        final offsets = _frequencyOffsets(
          trip,
          serviceDate,
          boundary,
          forward ? departureMinute : arrivalMinute,
          forward,
        );
        for (final offset in offsets) {
          final departure = serviceDate.add(
            Duration(minutes: departureMinute + offset),
          );
          var arrival = serviceDate.add(
            Duration(minutes: arrivalMinute + offset),
          );
          if (arrival.isBefore(departure)) {
            arrival = arrival.add(const Duration(days: 1));
          }
          final matches = forward
              ? !departure.isBefore(boundary)
              : !arrival.isAfter(boundary);
          if (!matches) continue;
          if (best != null) {
            final currentTime = forward
                ? best.departureTime!
                : best.arrivalTime!;
            final candidateTime = forward ? departure : arrival;
            if (forward
                ? !candidateTime.isBefore(currentTime)
                : !candidateTime.isAfter(currentTime)) {
              continue;
            }
          }
          best = JourneyLeg(
            route: template.route,
            from: template.from,
            to: template.to,
            stops: template.stops,
            durationMinutes: math.max(
              1,
              arrival.difference(departure).inMinutes,
            ),
            fare: template.fare,
            knownFare: template.knownFare,
            tripId: trip.id,
            headsign: trip.headsign,
            departureTime: departure,
            arrivalTime: arrival,
          );
          bestTrip = trip;
        }
      }

      if (best != null) {
        if (forward && dayOffset >= 0) {
          final nextServiceDay = DateTime(
            serviceDate.year,
            serviceDate.month,
            serviceDate.day + 1,
          );
          if (!best.departureTime!.isAfter(nextServiceDay)) break;
        } else if (!forward) {
          // Offsets are inspected newest-first, so once a matching arrival is
          // found no older service day can improve it.
          break;
        }
      }
    }
    final shapeId = bestTrip?.shapeId;
    if (best == null || shapeId == null) return best;
    return JourneyLeg(
      route: best.route,
      from: best.from,
      to: best.to,
      stops: best.stops,
      durationMinutes: best.durationMinutes,
      fare: best.fare,
      knownFare: best.knownFare,
      tripId: best.tripId,
      headsign: best.headsign,
      departureTime: best.departureTime,
      arrivalTime: best.arrivalTime,
      shapePoints: _shapeForLeg(
        template.route.shapes[shapeId] ?? const [],
        template.from,
        template.to,
      ),
    );
  }

  List<int> _frequencyOffsets(
    ScheduledTransitTrip trip,
    DateTime serviceDate,
    DateTime boundary,
    int comparisonMinute,
    bool forward,
  ) {
    if (trip.frequencyWindows.isEmpty) return const [0];
    int? firstDeparture;
    for (final value in trip.departureMinutes) {
      if (value != null) {
        firstDeparture = value;
        break;
      }
    }
    if (firstDeparture == null) return const [];
    final boundaryMinute = boundary.difference(serviceDate).inMinutes;
    final offsets = <int>[];
    for (final window in trip.frequencyWindows) {
      final initialOffset = window.startMinutes - firstDeparture;
      final initialComparison = comparisonMinute + initialOffset;
      var occurrence = forward
          ? ((boundaryMinute - initialComparison) / window.headwayMinutes)
                .ceil()
          : ((boundaryMinute - initialComparison) / window.headwayMinutes)
                .floor();
      occurrence = math.max(0, occurrence);
      final firstDepartureAtOccurrence =
          window.startMinutes + occurrence * window.headwayMinutes;
      if (firstDepartureAtOccurrence < window.endMinutes) {
        offsets.add(initialOffset + occurrence * window.headwayMinutes);
      }
    }
    return offsets;
  }

  bool _serviceRuns(String serviceId, DateTime date) {
    return _calendarsById[serviceId]?.runsOn(date) ?? true;
  }

  bool _isFreeRapidPenangRoute(TransitRoute route) {
    if (route.sourceId != 'rapid-penang') {
      return false;
    }
    const freeRoutes = {
      'CAT',
      'CT13',
      'CT14',
      'CT15',
    };
    return freeRoutes.contains(route.number.toUpperCase());
  }

  double? _rapidPenangFare(
      TransitRoute route,
      List<TransitPoint> shapePoints,
      List<TransitStop> stops,
      ) {
    if (route.sourceId != 'rapid-penang' ||
        route.mode != 'Bus') {
      return null;
    }
    if (_isFreeRapidPenangRoute(route)) {
      return 0;
    }
    var distanceMetres = 0.0;
    if (shapePoints.length >= 2) {
      for (var index = 0;
      index < shapePoints.length - 1;
      index++) {
        distanceMetres += _distanceBetween(
          shapePoints[index].latitude,
          shapePoints[index].longitude,
          shapePoints[index + 1].latitude,
          shapePoints[index + 1].longitude,
        );
      }
    } else {
      for (var index = 0; index < stops.length - 1; index++) {
        distanceMetres += _distanceBetween(
          stops[index].latitude,
          stops[index].longitude,
          stops[index + 1].latitude,
          stops[index + 1].longitude,
        );
      }
    }
    final distanceKm = distanceMetres / 1000;
    if (distanceKm <= 7) return 1.40;
    if (distanceKm <= 14) return 2.00;
    if (distanceKm <= 21) return 2.70;
    if (distanceKm <= 28) return 3.40;
    if (distanceKm <= 35) return 4.00;
    if (distanceKm <= 42) return 4.70;
    return 5.00;
  }
  JourneyLeg? _createLeg(TransitRoute route, TransitStop from, TransitStop to) {
    final fromIndex = route.stopIds.indexOf(from.id);
    final toIndex = route.stopIds.indexOf(to.id);

    if (fromIndex == -1 ||
        toIndex == -1 ||
        fromIndex >= toIndex) {
      return null;
    }

    final legStops = route.stopIds
        .sublist(fromIndex, toIndex + 1)
        .map((id) => _stopsById[id]!)
        .toList();

    final calculatePenangFare =
        route.sourceId == 'rapid-penang' &&
            route.mode == 'Bus';

    final fareShapePoints =
    calculatePenangFare &&
        route.shapes.isNotEmpty
        ? _shapeForLeg(
      route.shapes.values.first,
      from,
      to,
    )
        : const <TransitPoint>[];

    final calculatedFare = _rapidPenangFare(
      route,
      fareShapePoints,
      legStops,
    );

    final officialAdultCashFare =
        route.knownFare ??
        _adultCashFaresByStopPair[_fareLookupKey(
          route.sourceId,
          from.id,
          to.id,
        )];
    final fare = calculatedFare ?? officialAdultCashFare ?? route.baseFare;

    return JourneyLeg(
      route: route,
      from: from,
      to: to,
      stops: legStops,
      durationMinutes:
      math.max(1, legStops.length - 1) *
          route.minutesPerStop,
      fare: fare,
      knownFare: officialAdultCashFare ??
          (_isFreeRapidPenangRoute(route) ? fare : null),
    );
  }

  String _fareLookupKey(String sourceId, String fromStopId, String toStopId) {
    return '$sourceId\u001e$fromStopId\u001f$toStopId';
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

    for (
      var row = centreRow - cellRadius;
      row <= centreRow + cellRadius;
      row++
    ) {
      for (
        var column = centreColumn - cellRadius;
        column <= centreColumn + cellRadius;
        column++
      ) {
        nearbyStops.addAll(
          _stopsByGridCell['$row:$column'] ?? const <TransitStop>[],
        );
      }
    }

    final candidates = nearbyStops
        .map((stop) {
          final distance = _distanceBetween(
            location.latitude,
            location.longitude,
            stop.latitude,
            stop.longitude,
          ).round();
          return _StopCandidate(stop: stop, distanceMetres: distance);
        })
        .where((candidate) {
          return candidate.distanceMetres <= maximumWalkingMetres;
        })
        .toList();

    candidates.sort((a, b) => a.distanceMetres.compareTo(b.distanceMetres));

    // Keeping only the geographically closest stops can hide the one route
    // that connects a neighbourhood to the national network. For example,
    // the eight closest stops in Melor are served by D51/D61, while D62 (the
    // service that connects to KTM at Gua Musang) is a little farther away.
    // Keep the closest stops for normal local journeys, then add the nearest
    // stop for each additional service family. This broadens connectivity
    // without multiplying every origin/destination stop pair.
    const closestStopCount = 8;
    const maximumDiverseStopCount = 16;
    final selected = candidates.take(closestStopCount).toList();
    final coveredServiceIds = <String>{};

    void recordServices(_StopCandidate candidate) {
      for (final route
          in _routesByStopId[candidate.stop.id] ?? const <TransitRoute>[]) {
        coveredServiceIds.add('${route.sourceId}:${route.originalRouteId}');
      }
    }

    for (final candidate in selected) {
      recordServices(candidate);
    }
    for (final candidate in candidates.skip(closestStopCount)) {
      if (selected.length >= maximumDiverseStopCount) break;
      final serviceIds = (_routesByStopId[candidate.stop.id] ?? const [])
          .map((route) => '${route.sourceId}:${route.originalRouteId}')
          .toSet();
      if (serviceIds.isEmpty ||
          serviceIds.difference(coveredServiceIds).isEmpty) {
        continue;
      }
      selected.add(candidate);
      coveredServiceIds.addAll(serviceIds);
    }
    return selected;
  }

  Iterable<TransitStop> _stopsNearForTransfer(TransitStop source) sync* {
    const maximumDistanceMetres = 350;
    const gridSize = 0.005;
    final row = (source.latitude / gridSize).floor();
    final column = (source.longitude / gridSize).floor();
    for (var nearbyRow = row - 1; nearbyRow <= row + 1; nearbyRow++) {
      for (
        var nearbyColumn = column - 1;
        nearbyColumn <= column + 1;
        nearbyColumn++
      ) {
        for (final stop
            in _stopsByTransferGridCell['$nearbyRow:$nearbyColumn'] ??
                const <TransitStop>[]) {
          if (_distanceBetween(
                source.latitude,
                source.longitude,
                stop.latitude,
                stop.longitude,
              ) <=
              maximumDistanceMetres) {
            yield stop;
          }
        }
      }
    }
  }

  String _gridKey(double latitude, double longitude) {
    const gridSize = 0.05;
    final row = (latitude / gridSize).floor();
    final column = (longitude / gridSize).floor();
    return '$row:$column';
  }

  String _transferGridKey(double latitude, double longitude) {
    const gridSize = 0.005;
    final row = (latitude / gridSize).floor();
    final column = (longitude / gridSize).floor();
    return '$row:$column';
  }

  String _dedupGridKey(double latitude, double longitude) {
    const gridSize = 0.001;
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
    final latitudeDifference = (secondLatitude - firstLatitude) * math.pi / 180;
    final longitudeDifference =
        (secondLongitude - firstLongitude) * math.pi / 180;

    final value =
        math.sin(latitudeDifference / 2) * math.sin(latitudeDifference / 2) +
        math.cos(firstLatitudeRadians) *
            math.cos(secondLatitudeRadians) *
            math.sin(longitudeDifference / 2) *
            math.sin(longitudeDifference / 2);
    final safeValue = value.clamp(0.0, 1.0);
    final angle =
        2 * math.atan2(math.sqrt(safeValue), math.sqrt(1 - safeValue));
    return earthRadiusMetres * angle;
  }

  int _compareRecommended(JourneyOption first, JourneyOption second) {
    final shorterDuration = math.min(
      first.totalDurationMinutes,
      second.totalDurationMinutes,
    );
    final durationDifference =
        (first.totalDurationMinutes - second.totalDurationMinutes).abs();
    final materialDifference = math.max(15, (shorterDuration * 0.15).round());

    // A clearly faster journey should remain the recommended journey. Cost,
    // transfers and walking decide between alternatives with similar times.
    if (durationDifference >= materialDifference) {
      return first.totalDurationMinutes.compareTo(second.totalDurationMinutes);
    }

    final scoreResult = _recommendedScore(
      first,
    ).compareTo(_recommendedScore(second));
    if (scoreResult != 0) return scoreResult;
    return first.totalDurationMinutes.compareTo(second.totalDurationMinutes);
  }

  double _recommendedScore(JourneyOption option) {
    final farePenalty = option.knownTotalFare == null
        ? 1.0
        : option.knownTotalFare! * 2;
    return option.totalDurationMinutes +
        option.transferCount * 8 +
        option.walkingMetres / 150 +
        farePenalty;
  }

  List<TransitPoint> _shapeForLeg(
    List<TransitPoint> completeShape,
    TransitStop from,
    TransitStop to,
  ) {
    if (completeShape.length < 2) return const [];

    var nearestFromIndex = 0;
    var nearestFromDistance = double.infinity;
    var bestFromIndex = 0;
    var bestToIndex = 1;
    var bestPairDistance = double.infinity;

    for (var index = 0; index < completeShape.length; index++) {
      final point = completeShape[index];
      final fromDistance = _coordinateDistanceSquared(
        point.latitude,
        point.longitude,
        from.latitude,
        from.longitude,
      );
      if (fromDistance < nearestFromDistance) {
        nearestFromDistance = fromDistance;
        nearestFromIndex = index;
      }

      if (index <= nearestFromIndex) continue;
      final toDistance = _coordinateDistanceSquared(
        point.latitude,
        point.longitude,
        to.latitude,
        to.longitude,
      );
      final pairDistance = nearestFromDistance + toDistance;
      if (pairDistance < bestPairDistance) {
        bestPairDistance = pairDistance;
        bestFromIndex = nearestFromIndex;
        bestToIndex = index;
      }
    }

    if (bestPairDistance.isInfinite || bestToIndex <= bestFromIndex) {
      return const [];
    }
    final segment = completeShape.sublist(bestFromIndex, bestToIndex + 1);
    const maximumRenderedPoints = 250;
    final step = segment.length <= maximumRenderedPoints
        ? 1
        : (segment.length / maximumRenderedPoints).ceil();
    final result = <TransitPoint>[
      TransitPoint(latitude: from.latitude, longitude: from.longitude),
    ];
    for (var index = 0; index < segment.length; index += step) {
      result.add(segment[index]);
    }
    if (!identical(result.last, segment.last)) result.add(segment.last);
    result.add(TransitPoint(latitude: to.latitude, longitude: to.longitude));
    return result;
  }

  double _coordinateDistanceSquared(
    double firstLatitude,
    double firstLongitude,
    double secondLatitude,
    double secondLongitude,
  ) {
    final latitudeDifference = firstLatitude - secondLatitude;
    final longitudeDifference = firstLongitude - secondLongitude;
    return latitudeDifference * latitudeDifference +
        longitudeDifference * longitudeDifference;
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
    required this.transferMinutes,
  });

  final String id;
  final List<JourneyLeg> legs;
  final int originWalkingMetres;
  final int destinationWalkingMetres;
  final int walkingMetres;
  final List<int> transferMinutes;
}

class _TransferLink {
  const _TransferLink({required this.toStopId, required this.minimumMinutes});

  final String toStopId;
  final int minimumMinutes;
}

class _TransferPair {
  const _TransferPair({
    required this.fromStopId,
    required this.toStopId,
    required this.minimumMinutes,
    required this.walkingMetres,
  });

  final String fromStopId;
  final String toStopId;
  final int minimumMinutes;
  final int walkingMetres;
}

class _StopCandidate {
  const _StopCandidate({required this.stop, required this.distanceMetres});

  final TransitStop stop;
  final int distanceMetres;
}
