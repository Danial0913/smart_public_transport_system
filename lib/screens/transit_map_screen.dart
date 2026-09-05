import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

import '../data/local_storage_service.dart';
import '../data/transit_repository.dart';
import '../models/transit_models.dart';
import '../theme/app_theme.dart';
import '../data/geocoding_service.dart';
import '../data/location_service.dart';

class TransitMapScreen extends StatefulWidget {
  const TransitMapScreen({
    super.key,
    this.journey,
    this.initialRoute,
    this.onJourneyEnded,
    this.onRouteCleared,
  });

  final JourneyOption? journey;
  final TransitRoute? initialRoute;
  final VoidCallback? onJourneyEnded;
  final VoidCallback? onRouteCleared;

  @override
  State<TransitMapScreen> createState() => _TransitMapScreenState();
}

class _TransitMapScreenState extends State<TransitMapScreen> {
  final TransitRepository _repository = TransitRepository.instance;
  final GeocodingService _geocodingService = GeocodingService();
  final LocalStorageService _storage = LocalStorageService.instance;
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final Location _location = Location();
  final ValueNotifier<int> _searchVersion = ValueNotifier<int>(0);
  final RegExp _searchSpaces = RegExp(r'\s+');
  final Set<String> _favouriteRouteIds = {};
  StreamSubscription<LocationData>? _locationSubscription;
  Timer? _searchDebounce;
  Timer? _mapCameraDebounce;
  LocationData? _currentLocation;
  double _mapZoom = 11;
  static const double _markerZoomLevel = 15;

  bool _loading = true;
  bool _trackingLocation = false;
  bool _requestingLocation = false;
  bool _followUserLocation = true;
  bool _loadingMapArea = false;
  bool _savingCompletedJourney = false;
  bool _savingFavourite = false;
  bool _findingMapName = false;
  String? _error;
  String _selectedMode = 'All';
  String? _selectedMapName;
  LatLng? _selectedMapPoint;
  TransitStop? _selectedStop;
  TransitRoute? _selectedRoute;
  JourneyOption? _activeJourney;
  bool _mapReady = false;

  List<TransitStop> _stopSuggestions = [];
  List<TransitRoute> _routeSuggestions = [];
  List<TransitStop> _allStops = [];
  List<TransitRoute> _allRoutes = [];
  List<TransitStop> _renderedStops = [];
  List<Polyline> _renderedPolylines = [];
  final Map<String, List<TransitRoute>> _routesByStopId = {};
  final Map<String, List<TransitStop>> _routeStopsById = {};
  final Map<String, List<LatLng>> _routePointsById = {};
  final Map<String, String> _normalisedStopNames = {};
  final Map<String, String> _normalisedRouteNames = {};
  bool _showSuggestions = false;
  bool _isFreeRouteNumber(String routeNumber) {
    const freeRoutes = {
      'CAT',
      'CT13',
      'CT14',
      'CT15',
    };
    return freeRoutes.contains(
      routeNumber.toUpperCase(),
    );
  }
  final List<String> _transportModes = const [
    'All',
    'Bus',
    'Ferry',
    'KTM',
    'MRT',
    'LRT',
    'Monorail',
  ];

  @override
  void initState() {
    super.initState();
    _activeJourney = widget.journey;
    _selectedRoute = widget.initialRoute;
    _loadTransitData();
    _loadFavouriteRoutes();
  }

  @override
  void didUpdateWidget(covariant TransitMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final journey = widget.journey;
    if (journey == null || oldWidget.journey?.id == journey.id) return;

    setState(() {
      _clearMapPointSelection();
      _activeJourney = journey;
      _selectedStop = null;
      _selectedRoute = null;
      _selectedMode = 'All';
      _followUserLocation = false;
    });

    if (_mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusJourney(journey);
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _mapCameraDebounce?.cancel();
    _locationSubscription?.cancel();
    _searchVersion.dispose();
    _searchCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadTransitData() async {
    try {
      final journey = _activeJourney;
      await _repository.ensureDataNear(
        journey?.origin.latitude ?? 5.4145,
        journey?.origin.longitude ?? 100.3292,
      );
      await _refreshTransitCaches();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshTransitCaches() async {
    final allStops = _repository.stops;
    final allRoutes = _repository.routes;
    final routesByStopId = <String, List<TransitRoute>>{};
    final routeStopsById = <String, List<TransitStop>>{};
    final routePointsById = <String, List<LatLng>>{};
    final normalisedStopNames = <String, String>{};
    final normalisedRouteNames = <String, String>{};

    for (var index = 0; index < allStops.length; index++) {
      final stop = allStops[index];
      normalisedStopNames[stop.id] = _normaliseSearch(stop.name);
      if (index > 0 && index % 1000 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    for (var index = 0; index < allRoutes.length; index++) {
      final route = allRoutes[index];
      normalisedRouteNames[route.id] = _normaliseSearch(
        '${route.number} ${route.name}',
      );

      for (final stopId in route.stopIds) {
        routesByStopId.putIfAbsent(stopId, () => []).add(route);
      }

      final routeStops = _repository.stopsForRoute(route);
      routeStopsById[route.id] = routeStops;
      routePointsById[route.id] = routeStops.map((stop) {
        return LatLng(stop.latitude, stop.longitude);
      }).toList();
      if (index > 0 && index % 100 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (!mounted) return;
    setState(() {
      _allStops = allStops;
      _allRoutes = allRoutes;
      _routesByStopId
        ..clear()
        ..addAll(routesByStopId);
      _routeStopsById
        ..clear()
        ..addAll(routeStopsById);
      _routePointsById
        ..clear()
        ..addAll(routePointsById);
      _normalisedStopNames
        ..clear()
        ..addAll(normalisedStopNames);
      _normalisedRouteNames
        ..clear()
        ..addAll(normalisedRouteNames);
    });
  }

  List<TransitRoute> get _filteredRoutes {
    if (_selectedMode == 'All') {
      return _allRoutes;
    }

    return _allRoutes.where((route) {
      return route.mode == _selectedMode;
    }).toList();
  }

  List<TransitRoute> get _displayedRoutes {
    final journey = _activeJourney;
    if (journey != null) {
      final routesById = <String, TransitRoute>{};
      for (final leg in journey.legs) {
        routesById[leg.route.id] = leg.route;
      }
      return routesById.values.toList();
    }

    if (_selectedRoute != null) {
      return [_selectedRoute!];
    }

    return _filteredRoutes;
  }


  List<TransitRoute> _routesForStop(TransitStop stop) {
    return _routesByStopId[stop.id] ?? const <TransitRoute>[];
  }

  void _selectMode(String mode) {
    setState(() {
      _clearMapPointSelection();
      _activeJourney = null;
      _selectedMode = mode;
      _selectedStop = null;
      _selectedRoute = null;
    });

    final routes = _filteredRoutes;

    if (mode == 'All') {
      _mapController.move(const LatLng(4.20, 101.50), 6);
    } else if (routes.isNotEmpty) {
      final stops = _repository.stopsForRoute(routes.first);

      if (stops.isNotEmpty) {
        final firstStop = stops.first;

        _mapController.move(
          LatLng(firstStop.latitude, firstStop.longitude),
          10,
        );
      }
    }

    if (_searchCtrl.text.trim().length >= 2) {
      _onSearchChanged(_searchCtrl.text);
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = _normaliseSearch(value);

    if (query.length < 2 || _loading) {
      _clearSearchSuggestions();
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || _normaliseSearch(_searchCtrl.text) != query) return;
      _updateSearchSuggestions(query);
    });
  }

  void _updateSearchSuggestions(String query) {
    _stopSuggestions = _findStopSuggestions(query);
    _routeSuggestions = _findRouteSuggestions(query);
    _showSuggestions =
        _stopSuggestions.isNotEmpty || _routeSuggestions.isNotEmpty;
    _searchVersion.value++;
  }

  List<TransitStop> _findStopSuggestions(String query) {
    final matches = <TransitStop>[];

    for (final stop in _allStops) {
      if (_normalisedStopNames[stop.id]!.startsWith(query)) {
        matches.add(stop);
        if (matches.length == 5) return matches;
      }
    }

    for (final stop in _allStops) {
      final name = _normalisedStopNames[stop.id]!;
      if (!name.startsWith(query) && name.contains(query)) {
        matches.add(stop);
        if (matches.length == 5) break;
      }
    }

    return matches;
  }

  List<TransitRoute> _findRouteSuggestions(String query) {
    final matches = <TransitRoute>[];

    for (final route in _allRoutes) {
      if (_selectedMode != 'All' && route.mode != _selectedMode) continue;

      final name = _normalisedRouteNames[route.id]!;
      if (name.startsWith(query)) {
        matches.add(route);
        if (matches.length == 5) return matches;
      }
    }

    for (final route in _allRoutes) {
      if (_selectedMode != 'All' && route.mode != _selectedMode) continue;

      final name = _normalisedRouteNames[route.id]!;
      if (!name.startsWith(query) && name.contains(query)) {
        matches.add(route);
        if (matches.length == 5) break;
      }
    }

    return matches;
  }

  String _normaliseSearch(String value) {
    return value.trim().toLowerCase().replaceAll(_searchSpaces, ' ');
  }

  void _clearSearchSuggestions() {
    _stopSuggestions = [];
    _routeSuggestions = [];
    _showSuggestions = false;
    _searchVersion.value++;
  }
  Future<void> _selectMapPoint(
      LatLng point,
      ) async {
    if (_activeJourney != null) {
      _showMessage(
        'Close the active journey before selecting a map location.',
      );
      return;
    }

    if (!LocationService.isInsideMalaysia(
      point.latitude,
      point.longitude,
    )) {
      _showMessage(
        'Please select a location inside Malaysia.',
      );
      return;
    }

    setState(() {
      _selectedMapPoint = point;
      _selectedMapName = null;
      _findingMapName = true;
      _selectedStop = null;
      _selectedRoute = null;
      _followUserLocation = false;
    });

    widget.onRouteCleared?.call();

    final placeName =
    await _geocodingService.getPlaceName(
      point.latitude,
      point.longitude,
    );

    if (!mounted) return;

    final selectedPoint = _selectedMapPoint;

    if (selectedPoint == null ||
        selectedPoint.latitude != point.latitude ||
        selectedPoint.longitude != point.longitude) {
      return;
    }

    setState(() {
      _selectedMapName =
          placeName ?? 'Location name unavailable';
      _findingMapName = false;
    });
  }
  void _clearMapPointSelection() {
    _selectedMapPoint = null;
    _selectedMapName = null;
    _findingMapName = false;
  }
  void _onMapReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _mapReady = true;
      final camera = _mapController.camera;
      _refreshVisibleMapContent(camera);

      final journey = _activeJourney;
      final route = _selectedRoute;
      if (journey != null) {
        _focusJourney(journey);
      } else if (route != null) {
        _focusRoute(route);
      }
    });
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    _mapCameraDebounce?.cancel();
    _mapCameraDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || _loadingMapArea) return;
      _loadingMapArea = true;
      try {
        final added = await _repository.ensureDataNear(
          camera.center.latitude,
          camera.center.longitude,
        );
        if (added) await _refreshTransitCaches();
      } catch (_) {
      } finally {
        _loadingMapArea = false;
      }
      if (!mounted) return;
      final latestCamera = _mapController.camera;
      final movedToAnotherArea =
          (latestCamera.center.latitude - camera.center.latitude).abs() > 0.1 ||
              (latestCamera.center.longitude - camera.center.longitude).abs() > 0.1;
      if (movedToAnotherArea) {
        _onMapPositionChanged(latestCamera, true);
      } else {
        _refreshVisibleMapContent(latestCamera);
      }
    });
  }

  List<LatLng> _journeyLegPoints(JourneyLeg leg) {
    if (leg.shapePoints.isNotEmpty) {
      return leg.shapePoints.map((point) {
        return LatLng(
          point.latitude,
          point.longitude,
        );
      }).toList();
    }
    return leg.stops.map((stop) {
      return LatLng(
        stop.latitude,
        stop.longitude,
      );
    }).toList();
  }
  void _refreshVisibleMapContent(MapCamera camera) {
    final bounds = camera.visibleBounds;
    final zoom = camera.zoom;
    final journey = _activeJourney;
    final selectedRoute = _selectedRoute;
    final stops = <TransitStop>[];
    final polylines = <Polyline>[];

    if (journey != null && journey.legs.isNotEmpty) {
      final firstLeg = journey.legs.first;
      final lastLeg = journey.legs.last;

      _addWalkingPolyline(
        polylines,
        LatLng(journey.origin.latitude, journey.origin.longitude),
        LatLng(firstLeg.from.latitude, firstLeg.from.longitude),
      );

      for (var index = 0; index < journey.legs.length; index++) {
        final leg = journey.legs[index];
        polylines.add(
          Polyline(
            points: _journeyLegPoints(leg),
            color: _routeColour(leg.route.colourHex),
            strokeWidth: 6,
          ),
        );

        if (index < journey.legs.length - 1) {
          final nextLeg = journey.legs[index + 1];
          _addWalkingPolyline(
            polylines,
            LatLng(leg.to.latitude, leg.to.longitude),
            LatLng(nextLeg.from.latitude, nextLeg.from.longitude),
          );
        }
      }

      _addWalkingPolyline(
        polylines,
        LatLng(lastLeg.to.latitude, lastLeg.to.longitude),
        LatLng(journey.destination.latitude, journey.destination.longitude),
      );
    } else if (selectedRoute != null) {
      final routeStops =
          _routeStopsById[selectedRoute.id] ??
              const <TransitStop>[];
      if (zoom >= _markerZoomLevel) {
        stops.addAll(
          _sampleStops(routeStops, 80),
        );
      }
      polylines.add(
        _polylineForRoute(
          selectedRoute,
          selected: true,
        ),
      );
    } else if (zoom >= 8.5) {
      final maximumRoutes = zoom < 10
          ? 35
          : zoom < 12
          ? 60
          : 90;
      final maximumMarkers = zoom < 15
          ? 40
          : zoom < 17
          ? 80
          : 140;
      final visibleRoutes = <TransitRoute>[];

      for (final route in _displayedRoutes) {
        final points = _routePointsById[route.id] ?? const <LatLng>[];
        if (points.any(bounds.contains)) {
          visibleRoutes.add(route);
          if (visibleRoutes.length >= maximumRoutes) break;
        }
      }
      final visibleRouteIds = visibleRoutes
          .map((route) => route.id)
          .toSet();

      if (zoom >= _markerZoomLevel) {
        for (final stop in _allStops) {
          if (!bounds.contains(
            LatLng(
              stop.latitude,
              stop.longitude,
            ),
          )) {
            continue;
          }
          final stopRoutes =
              _routesByStopId[stop.id] ??
                  const <TransitRoute>[];

          if (stopRoutes.any(
                (route) {
              return visibleRouteIds.contains(
                route.id,
              );
            },
          )) {
            stops.add(stop);

            if (stops.length >= maximumMarkers) {
              break;
            }
          }
        }
      }

      for (final route in visibleRoutes) {
        polylines.add(
          _polylineForRoute(route),
        );
      }
    }

    final selectedStop = _selectedStop;
    if (zoom >= _markerZoomLevel &&
        selectedStop != null &&
        !stops.any(
              (stop) => stop.id == selectedStop.id,
        )) {
      stops.add(selectedStop);
    }

    if (!mounted) return;
    setState(() {
      _mapZoom = zoom;
      _renderedStops = stops;
      _renderedPolylines = polylines;
    });
  }

  Polyline _polylineForRoute(TransitRoute route, {bool selected = false}) {
    return Polyline(
      points: _routePointsById[route.id] ?? const <LatLng>[],
      color: _routeColour(route.colourHex).withValues(
        alpha: selected ? 1 : 0.65,
      ),
      strokeWidth: selected ? 6 : 4,
    );
  }

  List<TransitStop> _sampleStops(List<TransitStop> stops, int maximum) {
    if (stops.length <= maximum) return List<TransitStop>.from(stops);

    final sampled = <TransitStop>[];
    final step = (stops.length / maximum).ceil();
    for (var index = 0; index < stops.length; index += step) {
      sampled.add(stops[index]);
    }
    if (sampled.last.id != stops.last.id) sampled.add(stops.last);
    return sampled;
  }

  void _focusRoute(TransitRoute route) {
    final points =
        _routePointsById[route.id] ?? const <LatLng>[];

    if (points.length < 2) return;

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(
          40,
          70,
          40,
          190,
        ),
        maxZoom: 15,
      ),
    );
  }

  void _focusJourney(JourneyOption journey) {
    final points = <LatLng>[
      LatLng(
        journey.origin.latitude,
        journey.origin.longitude,
      ),

      for (final leg in journey.legs)
        ..._journeyLegPoints(leg),

      LatLng(
        journey.destination.latitude,
        journey.destination.longitude,
      ),
    ];

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(
          40,
          70,
          40,
          190,
        ),
        maxZoom: 15,
      ),
    );
  }

  void _selectStopSuggestion(TransitStop stop) {
    FocusScope.of(context).unfocus();

    setState(() {
      _clearMapPointSelection();
      _activeJourney = null;
      _searchCtrl.text = stop.name;
      _selectedStop = stop;
      _selectedRoute = null;
      _stopSuggestions = [];
      _routeSuggestions = [];
      _showSuggestions = false;
      _followUserLocation = false;
    });

    _mapController.move(LatLng(stop.latitude, stop.longitude), 14);
  }

  void _selectRouteSuggestion(TransitRoute route) {
    FocusScope.of(context).unfocus();

    setState(() {
      _activeJourney = null;
      _searchCtrl.text = '${route.mode} ${route.number}';
      _stopSuggestions = [];
      _routeSuggestions = [];
      _showSuggestions = false;
      _followUserLocation = false;
    });

    _showRoute(route);
  }

  void _search() {
    final query = _searchCtrl.text.trim();

    if (query.isEmpty) return;

    _searchDebounce?.cancel();
    _updateSearchSuggestions(_normaliseSearch(query));

    if (_stopSuggestions.isNotEmpty) {
      _selectStopSuggestion(_stopSuggestions.first);
      return;
    }

    if (_routeSuggestions.isNotEmpty) {
      _selectRouteSuggestion(_routeSuggestions.first);
      return;
    }

    FocusScope.of(context).unfocus();

    _clearSearchSuggestions();

    _showMessage('No matching station, stop, or route found.');
  }

  Future<void> _loadFavouriteRoutes() async {
    try {
      final favourites = await _storage.getFavourites();

      final routeIds = favourites
          .where((favourite) {
        return favourite.type == 'Route';
      })
          .map((favourite) {
        return favourite.referenceId;
      })
          .toSet();

      if (!mounted) return;

      setState(() {
        _favouriteRouteIds
          ..clear()
          ..addAll(routeIds);
      });
    } catch (error) {
      if (mounted) {
        _showMessage('Unable to load favourites.');
      }
    }
  }
  Future<void> _toggleRouteFavourite(
      TransitRoute route,
      ) async {
    if (_savingFavourite) return;

    setState(() {
      _savingFavourite = true;
    });

    try {
      final favourites = await _storage.getFavourites();

      FavouriteItem? existingFavourite;

      for (final favourite in favourites) {
        if (favourite.type == 'Route' &&
            favourite.referenceId == route.id) {
          existingFavourite = favourite;
          break;
        }
      }

      if (existingFavourite != null) {
        await _storage.deleteFavourite(
          existingFavourite.id,
        );

        if (!mounted) return;

        setState(() {
          _favouriteRouteIds.remove(route.id);
        });

        _showMessage(
          'Route ${route.number} removed from favourites.',
        );

        return;
      }

      final categories =
      await _storage.getFavouriteCategories();

      if (!mounted) return;

      if (categories.isEmpty) {
        _showMessage(
          'No favourite category is available.',
        );
        return;
      }

      final selectedCategory =
      await showDialog<FavouriteCategory>(
        context: context,
        builder: (dialogContext) {
          return SimpleDialog(
            title: const Text('Select a category'),
            children: categories.map((category) {
              return SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    category,
                  );
                },
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 10,
                    backgroundColor:
                    Color(category.colourValue),
                  ),
                  title: Text(category.name),
                ),
              );
            }).toList(),
          );
        },
      );

      if (selectedCategory == null || !mounted) {
        return;
      }

      final favourite = FavouriteItem(
        id: 'favourite-'
            '${DateTime.now().microsecondsSinceEpoch}',
        title: route.number,
        subtitle: route.name,
        type: 'Route',
        referenceId: route.id,
        categoryId: selectedCategory.id,
        createdAt: DateTime.now(),
      );

      await _storage.addFavourite(favourite);

      if (!mounted) return;

      setState(() {
        _favouriteRouteIds.add(route.id);
      });

      _showMessage(
        'Route ${route.number} saved to '
            '${selectedCategory.name}.',
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Unable to update this favourite.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingFavourite = false;
        });
      }
    }
  }

  void _showRoute(TransitRoute route) {
    final stops = _repository.stopsForRoute(route);

    setState(() {
      _clearMapPointSelection();
      _activeJourney = null;
      _selectedRoute = route;
      _selectedStop = null;
      _selectedMode = route.mode;
    });

    if (stops.isNotEmpty) {
      final firstStop = stops.first;

      _mapController.move(LatLng(firstStop.latitude, firstStop.longitude), 11);
    }
    if (_mapReady) {
      _focusRoute(route);
    }
  }

  void _showAllRoutes() {
    setState(() {
      _clearMapPointSelection();
      _activeJourney = null;
      _selectedRoute = null;
      _selectedStop = null;
    });
    widget.onRouteCleared?.call();
    if (_mapReady) {
      _refreshVisibleMapContent(_mapController.camera);
    }
  }

  Future<bool> _prepareLocationService() async {
    final permissionStatus = await handler.Permission.locationWhenInUse
        .request();

    if (permissionStatus != handler.PermissionStatus.granted) {
      if (mounted) {
        _showMessage('Location permission was not granted.');
      }

      return false;
    }

    var serviceEnabled = await _location.serviceEnabled();

    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
    }

    if (!serviceEnabled) {
      if (mounted) {
        _showMessage('Please enable GPS to use live tracking.');
      }

      return false;
    }

    return true;
  }

  Future<void> _startLocationTracking() async {
    if (_trackingLocation || _requestingLocation) return;

    setState(() {
      _requestingLocation = true;
    });

    try {
      final ready = await _prepareLocationService();

      if (!ready || !mounted) return;

      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 2000,
        distanceFilter: 10,
      );

      final firstLocation = await _location.getLocation();

      if (!mounted) return;

      _updateCurrentLocation(firstLocation);

      await _locationSubscription?.cancel();

      _locationSubscription = _location.onLocationChanged.listen(
        _updateCurrentLocation,
        onError: (Object error) {
          if (mounted) {
            _showMessage('Location tracking error: $error');
          }
        },
      );

      setState(() {
        _trackingLocation = true;
        _followUserLocation = true;
      });

      _showMessage('Live location tracking started.');
    } catch (error) {
      if (mounted) {
        _showMessage('Unable to start location tracking: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _requestingLocation = false;
        });
      }
    }
  }

  void _updateCurrentLocation(LocationData location) {
    if (!mounted) return;

    final latitude = location.latitude;
    final longitude = location.longitude;

    setState(() {
      _currentLocation = location;
    });

    if (_followUserLocation) {
      _mapController.move(LatLng(latitude, longitude), 15);
    }
  }

  Future<void> _stopLocationTracking() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;

    if (!mounted) return;

    setState(() {
      _trackingLocation = false;
      _followUserLocation = false;
    });

    _showMessage('Live location tracking stopped.');
  }

  void _moveToCurrentLocation() {
    final latitude = _currentLocation?.latitude;
    final longitude = _currentLocation?.longitude;

    if (latitude == null || longitude == null) {
      _startLocationTracking();
      return;
    }

    setState(() {
      _followUserLocation = true;
    });

    _mapController.move(LatLng(latitude, longitude), 15);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchSection(),
        _buildTransportFilters(),
        Expanded(child: _buildMapSection()),
      ],
    );
  }

  Widget _buildSearchSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: ValueListenableBuilder<int>(
        valueListenable: _searchVersion,
        builder: (context, version, child) {
          return Column(
            children: [
              TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onTap: () {
                  if (_searchCtrl.text.trim().length >= 2) {
                    _onSearchChanged(_searchCtrl.text);
                  }
                },
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Search station, stop, or route',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchCtrl.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _searchDebounce?.cancel();
                            _searchCtrl.clear();
                            _clearSearchSuggestions();
                          },
                          icon: const Icon(Icons.close),
                        ),
                      IconButton(
                        tooltip: 'Search',
                        onPressed: _search,
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showSuggestions) _buildSearchSuggestions(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchSuggestions() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          ..._stopSuggestions.map((stop) {
            final routes = _routesForStop(stop);
            final modes = routes.map((route) => route.mode).toSet();
            final routeNumbers = routes.map((route) => route.number).join(', ');

            return ListTile(
              leading: Icon(
                _iconForModes(modes),
                color: _colourForModes(modes),
              ),
              title: Text(
                stop.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                routeNumbers.isEmpty
                    ? _stationType(modes)
                    : '${_stationType(modes)} · Routes $routeNumbers',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _selectStopSuggestion(stop),
            );
          }),
          ..._routeSuggestions.map((route) {
            return ListTile(
              leading: Icon(
                _iconForMode(route.mode),
                color: _routeColour(route.colourHex),
              ),
              title: Text('${route.mode} ${route.number}'),
              subtitle: Text(
                route.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _selectRouteSuggestion(route),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTransportFilters() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _transportModes.map((mode) {
            final isSelected = _selectedMode == mode;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(mode),
                selected: isSelected,
                selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                checkmarkColor: AppTheme.primaryBlue,
                side: BorderSide(
                  color: isSelected ? AppTheme.primaryBlue : AppTheme.border,
                ),
                labelStyle: TextStyle(
                  color: isSelected
                      ? AppTheme.primaryBlue
                      : AppTheme.secondaryText,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                onSelected: (_) => _selectMode(mode),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMapSection() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Unable to load transit data',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });

                  _loadTransitData();
                },
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(5.4145, 100.3292),
            initialZoom: 11,
            minZoom: 5,
            maxZoom: 19,
            onMapReady: _onMapReady,
            onPositionChanged: _onMapPositionChanged,
            onTap: (tapPosition, point) {_selectMapPoint(point);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName:
              'my.edu.tarumt.smart_public_transport_system',
              maxZoom: 19,
              panBuffer: 0,
            ),
            PolylineLayer(polylines: _renderedPolylines),
            if (_mapZoom >= _markerZoomLevel)
              MarkerLayer(
                markers: _renderedStops
                    .map(_buildStopMarker)
                    .toList(),
              ),
            if (_mapZoom >= _markerZoomLevel)
              MarkerLayer(
                markers: _buildJourneyStationMarkers(),
              ),
            MarkerLayer(
              markers: _buildJourneyEndpointMarkers(),
            ),
            MarkerLayer(
              markers: _buildSelectedMapPointMarkers(),
            ),
            MarkerLayer(
              markers: _buildCurrentLocationMarkers(),
            ),
            const Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: ColoredBox(
                  color: Colors.white70,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(fontSize: 9),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(left: 12, top: 12, child: _buildMapStatus()),
        Positioned(
          right: 12,
          top: 42,
          child: Column(
            children: [
              _buildMapControlButton(
                tooltip: 'Show Penang',
                icon: Icons.location_city,
                onPressed: () {
                  setState(() {
                    _followUserLocation = false;
                  });

                  _mapController.move(const LatLng(5.4145, 100.3292), 11);
                },
              ),
              const SizedBox(height: 8),
              _buildMapControlButton(
                tooltip: 'Show Malaysia',
                icon: Icons.public,
                onPressed: () {
                  setState(() {
                    _followUserLocation = false;
                  });

                  _mapController.move(const LatLng(4.20, 101.50), 6);
                },
              ),
              const SizedBox(height: 8),
              _buildMapControlButton(
                tooltip: _trackingLocation
                    ? 'Stop live tracking'
                    : 'Start live tracking',
                icon: _requestingLocation
                    ? Icons.hourglass_top
                    : _trackingLocation
                    ? Icons.location_off
                    : Icons.my_location,
                onPressed: _requestingLocation
                    ? null
                    : _trackingLocation
                    ? _stopLocationTracking
                    : _startLocationTracking,
              ),
              if (_currentLocation != null) ...[
                const SizedBox(height: 8),
                _buildMapControlButton(
                  tooltip: 'Move to my location',
                  icon: Icons.gps_fixed,
                  onPressed: _moveToCurrentLocation,
                ),
              ],
              if (_selectedRoute != null) ...[
                const SizedBox(height: 8),
                _buildMapControlButton(
                  tooltip: 'Show all routes',
                  icon: Icons.layers_outlined,
                  onPressed: _showAllRoutes,
                ),
              ],
            ],
          ),
        ),
        if (_selectedMapPoint != null &&
            _selectedStop == null &&
            _selectedRoute == null &&
            _activeJourney == null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildMapPointInformation(),
          ),
        if (_selectedStop != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildStopInformation(
              _selectedStop!,
            ),
          ),
        if (_selectedStop == null &&
            _selectedRoute != null &&
            _activeJourney == null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildRouteInformation(
              _selectedRoute!,
            ),
          ),
        if (_selectedStop == null &&
            _selectedRoute == null &&
            _activeJourney != null)
          Positioned.fill(
            child: _buildDraggableJourneyPanel(
              _activeJourney!,
            ),
          ),
      ],
    );
  }

  void _addWalkingPolyline(List<Polyline> polylines, LatLng from, LatLng to) {
    if ((from.latitude - to.latitude).abs() < 0.000001 &&
        (from.longitude - to.longitude).abs() < 0.000001) {
      return;
    }

    polylines.add(
      Polyline(
        points: [from, to],
        color: const Color(0xFF616161),
        strokeWidth: 4,
      ),
    );
  }

  Marker _buildStopMarker(TransitStop stop) {
    final routes = _routesForStop(stop);
    final modes = routes.map((route) => route.mode).toSet();
    final isSelected = _selectedStop?.id == stop.id;

    return Marker(
      point: LatLng(stop.latitude, stop.longitude),
      width: 52,
      height: 52,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _selectedStop = stop;
            _followUserLocation = false;
          });
        },
        child: Tooltip(
          message: stop.name,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.red : _colourForModes(modes),
                width: isSelected ? 4 : 3,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              _iconForModes(modes),
              size: isSelected ? 30 : 26,
              color: isSelected ? Colors.red : _colourForModes(modes),
            ),
          ),
        ),
      ),
    );
  }

  List<Marker> _buildSelectedMapPointMarkers() {
    final point = _selectedMapPoint;

    if (point == null) {
      return [];
    }

    return [
      Marker(
        point: point,
        width: 52,
        height: 52,
        child: Tooltip(
          message: _findingMapName
              ? 'Finding location...'
              : _selectedMapName ??
              'Selected location',
          child: const Icon(
            Icons.location_pin,
            color: Colors.red,
            size: 48,
          ),
        ),
      ),
    ];
  }

  List<Marker> _buildJourneyStationMarkers() {
    final journey = _activeJourney;
    if (journey == null || journey.legs.isEmpty) return [];

    final markers = <Marker>[
      _buildJourneyStationMarker(
        stop: journey.legs.first.from,
        label:
        'Board ${journey.legs.first.route.number} at ${journey.legs.first.from.name}',
        icon: _iconForMode(journey.legs.first.route.mode),
        colour: _routeColour(journey.legs.first.route.colourHex),
      ),
    ];

    for (int index = 0; index < journey.legs.length - 1; index++) {
      final currentLeg = journey.legs[index];
      final nextLeg = journey.legs[index + 1];

      markers.add(
        _buildJourneyStationMarker(
          stop: currentLeg.to,
          label:
          'Change from ${currentLeg.route.number} to ${nextLeg.route.number} at ${currentLeg.to.name}',
          icon: Icons.transfer_within_a_station,
          colour: const Color(0xFFF57C00),
        ),
      );

      if (currentLeg.to.id != nextLeg.from.id) {
        markers.add(
          _buildJourneyStationMarker(
            stop: nextLeg.from,
            label:
            'Walk and board ${nextLeg.route.number} at ${nextLeg.from.name}',
            icon: Icons.directions_walk,
            colour: const Color(0xFF616161),
          ),
        );
      }
    }

    markers.add(
      _buildJourneyStationMarker(
        stop: journey.legs.last.to,
        label:
        'Leave ${journey.legs.last.route.number} at ${journey.legs.last.to.name}',
        icon: Icons.stop_circle_outlined,
        colour: _routeColour(journey.legs.last.route.colourHex),
      ),
    );

    return markers;
  }

  Marker _buildJourneyStationMarker({
    required TransitStop stop,
    required String label,
    required IconData icon,
    required Color colour,
  }) {
    return Marker(
      point: LatLng(stop.latitude, stop.longitude),
      width: 56,
      height: 56,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _selectedStop = stop;
            _followUserLocation = false;
          });
        },
        child: Tooltip(
          message: label,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: colour, width: 4),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: colour, size: 28),
          ),
        ),
      ),
    );
  }

  List<Marker> _buildJourneyEndpointMarkers() {
    final journey = _activeJourney;
    if (journey == null) return [];

    return [
      _buildJourneyEndpointMarker(
        location: journey.origin,
        label: 'Start: ${journey.origin.name}',
        icon: Icons.trip_origin,
        colour: Colors.green,
      ),
      _buildJourneyEndpointMarker(
        location: journey.destination,
        label: 'Destination: ${journey.destination.name}',
        icon: Icons.flag,
        colour: Colors.red,
      ),
    ];
  }

  Marker _buildJourneyEndpointMarker({
    required JourneyLocation location,
    required String label,
    required IconData icon,
    required Color colour,
  }) {
    return Marker(
      point: LatLng(location.latitude, location.longitude),
      width: 54,
      height: 54,
      child: Tooltip(
        message: label,
        child: Container(
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 27),
        ),
      ),
    );
  }

  List<Marker> _buildCurrentLocationMarkers() {
    final latitude = _currentLocation?.latitude;
    final longitude = _currentLocation?.longitude;

    if (latitude == null || longitude == null) {
      return [];
    }

    return [
      Marker(
        point: LatLng(latitude, longitude),
        width: 48,
        height: 48,
        child: const CurrentUserLocationMarker(),
      ),
    ];
  }

  Widget _buildMapStatus() {
    final route = _selectedRoute;
    final journey = _activeJourney;

    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _trackingLocation
                ? Icons.gps_fixed
                : journey != null
                ? Icons.navigation
                : route == null
                ? Icons.map_outlined
                : Icons.route,
            size: 18,
            color: _trackingLocation ? Colors.green : AppTheme.primaryBlue,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              _trackingLocation
                  ? 'Live location active'
                  : journey != null
                  ? 'Journey ${journey.routeSummary}'
                  : route == null
                  ? _mapZoom < _markerZoomLevel
                  ? 'Zoom in to view stops'
                  : '${_renderedStops.length} nearby stops'
                  : 'Route ${route.number}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapControlButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: onPressed == null
              ? AppTheme.secondaryText
              : AppTheme.primaryBlue,
        ),
      ),
    );
  }
  Future<double?> _getBudgetExceededAmount() async {
    final now = DateTime.now();

    final budget =
    await _storage.getMonthlyTravelBudget(now);

    if (budget == null || budget <= 0) {
      return null;
    }

    final monthStart = DateTime(
      now.year,
      now.month,
    );

    final nextMonth = DateTime(
      now.year,
      now.month + 1,
    );

    final completedJourneys =
    await _storage.getCompletedJourneys(
      start: monthStart,
      end: nextMonth,
    );

    var monthlySpending = 0.0;

    for (final completedJourney
    in completedJourneys) {
      monthlySpending += completedJourney.fare;
    }

    final exceededAmount =
        monthlySpending - budget;

    if (exceededAmount <= 0) {
      return null;
    }

    return exceededAmount;
  }
  Future<void> _completeJourney() async {
    final journey = _activeJourney;

    if (journey == null || _savingCompletedJourney) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.flag_circle,
            color: Colors.green,
            size: 44,
          ),
          title: const Text(
            'Complete Journey?',
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${journey.origin.name} to ${journey.destination.name}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.mainText,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Route: ${journey.routeSummary}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                '${journey.totalDurationMinutes} min · '
                'RM${journey.totalFare.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              const Text(
                'This journey will be added to your travel history and '
                'analytics.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.secondaryText),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Continue Journey'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.check),
              label: const Text('Complete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _savingCompletedJourney = true);

    try {
      await _storage.recordCompletedJourney(
        journey,
      );

      double? budgetExceededAmount;

      try {
        budgetExceededAmount =
        await _getBudgetExceededAmount();
      } catch (_) {
        budgetExceededAmount = null;
      }

      if (!mounted) return;

      setState(() {
        _activeJourney = null;
        _selectedStop = null;
        _selectedRoute = null;
        _savingCompletedJourney = false;
      });

      if (_mapReady) {
        _refreshVisibleMapContent(
          _mapController.camera,
        );
      }

      if (budgetExceededAmount != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 6),
            content: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Journey saved. You have exceeded '
                        'your monthly transport budget by '
                        'RM${budgetExceededAmount.toStringAsFixed(2)}.',
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Journey saved to travel history.',
            ),
          ),
        );
      }

      widget.onJourneyEnded?.call();
    } catch (error) {
      if (!mounted) return;

      setState(() => _savingCompletedJourney = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to save journey: $error'),
        ),
      );
    }
  }

  Widget _buildDraggableJourneyPanel(
      JourneyOption journey,
      ) {
    return DraggableScrollableSheet(
      initialChildSize: 0.70,
      minChildSize: 0.042,
      maxChildSize: 0.70,
      expand: false,
      snap: true,
      snapSizes: const [
        0.07,
        0.55,
        0.65,
      ],
      builder: (context, scrollCtrl) {
        return Material(
          color: Colors.white,
          elevation: 10,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(
              12,
              8,
              12,
              16,
            ),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              const SizedBox(height: 4),

              _buildJourneyInformation(journey),
            ],
          ),
        );
      },
    );
  }
  Widget _buildJourneyInformation(JourneyOption journey) {
    return _buildInformationCard(
      icon: Icons.navigation,
      colour: AppTheme.primaryBlue,
      title: '${journey.origin.name} to ${journey.destination.name}',
      subtitle: journey.legs.length == 1
          ? 'Direct transport journey'
          : '${journey.legs.length} transport legs',
      onClose: () {
        setState(() => _activeJourney = null);
        if (_mapReady) {
          _refreshVisibleMapContent(_mapController.camera);
        }
        widget.onJourneyEnded?.call();
      },
      children: [
        _buildJourneySequence(journey),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            Chip(
              avatar: const Icon(Icons.schedule, size: 18),
              label: Text('${journey.totalDurationMinutes} min'),
            ),
            Chip(
              avatar: const Icon(Icons.payments_outlined, size: 18),
              label: Text('RM${journey.totalFare.toStringAsFixed(2)}'),
            ),
            Chip(
              avatar: const Icon(Icons.transfer_within_a_station, size: 18),
              label: Text('${journey.transferCount} transfer(s)'),
            ),
            Chip(
              avatar: const Icon(Icons.directions_walk, size: 18),
              label: Text('${journey.walkingMetres} m'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _focusJourney(journey),
            icon: const Icon(Icons.center_focus_strong),
            label: const Text('Show Entire Journey'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _savingCompletedJourney ? null : _completeJourney,
            icon: _savingCompletedJourney
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.flag),
            label: Text(
              _savingCompletedJourney
                  ? 'Saving Journey...'
                  : 'Complete Journey',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildJourneySequence(JourneyOption journey) {
    final steps = <Widget>[];

    void addStep(Widget step) {
      if (steps.isNotEmpty) {
        steps.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 3),
            child: Icon(
              Icons.chevron_right,
              size: 18,
              color: AppTheme.secondaryText,
            ),
          ),
        );
      }
      steps.add(step);
    }

    if (journey.originWalkingMetres > 0) {
      addStep(
        _buildJourneyStepChip(
          icon: Icons.directions_walk,
          label: '${journey.originWalkingMetres} m',
          colour: Colors.grey.shade700,
        ),
      );
    }

    for (var index = 0; index < journey.legs.length; index++) {
      final leg = journey.legs[index];
      addStep(
        _buildJourneyStepChip(
          icon: _iconForMode(leg.route.mode),
          label: leg.route.number,
          colour: _routeColour(leg.route.colourHex),
        ),
      );

      if (index < journey.legs.length - 1) {
        final nextLeg = journey.legs[index + 1];
        if (leg.to.id != nextLeg.from.id) {
          addStep(
            _buildJourneyStepChip(
              icon: Icons.directions_walk,
              label: 'Walk',
              colour: Colors.grey.shade700,
            ),
          );
        }
      }
    }

    if (journey.destinationWalkingMetres > 0) {
      addStep(
        _buildJourneyStepChip(
          icon: Icons.directions_walk,
          label: '${journey.destinationWalkingMetres} m',
          colour: Colors.grey.shade700,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: steps),
    );
  }

  Widget _buildJourneyStepChip({
    required IconData icon,
    required String label,
    required Color colour,
  }) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 17, color: colour),
      label: Text(
        label,
        style: TextStyle(color: colour, fontWeight: FontWeight.bold),
      ),
      backgroundColor: colour.withValues(alpha: 0.10),
      side: BorderSide(color: colour.withValues(alpha: 0.35)),
    );
  }
  Widget _buildMapPointInformation() {
    final point = _selectedMapPoint!;

    final name = _findingMapName
        ? 'Finding location...'
        : _selectedMapName ??
        'Selected location';

    return _buildInformationCard(
      icon: Icons.location_pin,
      colour: Colors.red,
      title: name,
      subtitle:
      '${point.latitude.toStringAsFixed(6)}, '
          '${point.longitude.toStringAsFixed(6)}',
      onClose: () {
        setState(() {
          _clearMapPointSelection();
        });
      },
      children: [
        Row(
          children: [
            const SizedBox(
              width: 85,
              child: Text(
                'Latitude',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                ),
              ),
            ),
            Text(
              point.latitude.toStringAsFixed(6),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 85,
              child: Text(
                'Longitude',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                ),
              ),
            ),
            Text(
              point.longitude.toStringAsFixed(6),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
  Widget _buildStopInformation(TransitStop stop) {
    final routes = _routesForStop(stop);
    final modes = routes.map((route) => route.mode).toSet();
    final stationType = modes.length > 1
        ? 'Transport interchange'
        : _stationType(modes);

    return _buildInformationCard(
      icon: _iconForModes(modes),
      colour: _colourForModes(modes),
      title: stop.name,
      subtitle:
      '$stationType · ${stop.accessible ? "Accessible" : "Accessibility unavailable"}',
      onClose: () {
        setState(() => _selectedStop = null);
      },
      children: [
        if (routes.isEmpty)
          const Text(
            'No route information is available for this stop.',
            style: TextStyle(color: AppTheme.secondaryText),
          )
        else ...[
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Select a route',
                  style: TextStyle(
                    color: AppTheme.mainText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(Icons.swipe, size: 19, color: AppTheme.secondaryText),
              SizedBox(width: 4),
              Text(
                'Swipe',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              itemCount: routes.length,
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 6,
                mainAxisExtent: 94,
              ),
              itemBuilder: (context, index) {
                final route = routes[index];
                final routeColour = _routeColour(route.colourHex);
                return Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      _iconForMode(route.mode),
                      size: 17,
                      color: routeColour,
                    ),
                    label: Text(
                      route.number,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    tooltip: '${route.mode} ${route.number}: ${route.name}',
                    onPressed: () => _showRoute(route),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRouteInformation(TransitRoute route) {
    final stops = _repository.stopsForRoute(route);
    final firstStop = stops.isEmpty ? 'Unknown' : stops.first.name;
    final lastStop = stops.isEmpty ? 'Unknown' : stops.last.name;
    final isFavourite = _favouriteRouteIds.contains(route.id);
    return _buildInformationCard(
      icon: _iconForMode(route.mode),
      colour: _routeColour(route.colourHex),
      title: '${route.mode} ${route.number}',
      subtitle: route.name,
      onClose: _showAllRoutes,
      children: [
        Row(
          children: [
            const Icon(Icons.route, size: 19, color: AppTheme.primaryBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$firstStop → $lastStop',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.mainText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            Chip(
              avatar: const Icon(Icons.location_on_outlined, size: 18),
              label: Text('${stops.length} stops'),
            ),
            Chip(
              avatar: const Icon(Icons.payments_outlined, size: 18),
              label: Text(
                route.sourceId == 'rapid-penang' &&
                    route.mode == 'Bus'
                    ? _isFreeRouteNumber(route.number)
                    ? 'Free'
                    : 'From RM1.40'
                    : route.knownFare != null
                    ? 'RM${route.knownFare!.toStringAsFixed(2)}'
                    : 'Fare unavailable',
              ),            ),
            Chip(
              avatar: const Icon(Icons.schedule, size: 18),
              label: Text('Every ${route.frequencyMinutes} min'),
            ),
            if (route.accessible)
              const Chip(
                avatar: Icon(Icons.accessible, size: 18),
                label: Text('Accessible'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: isFavourite
                  ? Colors.red.shade700
                  : AppTheme.primaryBlue,
            ),
            onPressed: _savingFavourite
                ? null
                : () {
              _toggleRouteFavourite(route);
            },
            icon: _savingFavourite
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : Icon(
              isFavourite
                  ? Icons.bookmark_remove
                  : Icons.bookmark_add_outlined,
            ),
            label: Text(
              _savingFavourite
                  ? 'Updating...'
                  : isFavourite
                  ? 'Remove Favourite'
                  : 'Save to Favourite',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInformationCard({
    required IconData icon,
    required Color colour,
    required String title,
    required String subtitle,
    required VoidCallback onClose,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 6,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              minVerticalPadding: 0,
              leading: CircleAvatar(
                backgroundColor: colour.withValues(alpha: 0.12),
                child: Icon(icon, color: colour),
              ),
              title: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.mainText,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.secondaryText),
              ),
              trailing: IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ),
            if (children.isNotEmpty) ...[
              const Divider(height: 8),
              const SizedBox(height: 6),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
  IconData _iconForModes(Set<String> modes) {
    if (modes.length > 1) {
      return Icons.hub;
    }

    if (modes.isEmpty) {
      return Icons.location_on;
    }

    return _iconForMode(modes.first);
  }

  IconData _iconForMode(String mode) {
    switch (mode) {
      case 'Bus':
        return Icons.directions_bus;
      case 'Ferry':
        return Icons.directions_boat;
      case 'KTM':
      case 'MRT':
      case 'LRT':
      case 'Monorail':
        return Icons.train;
      default:
        return Icons.location_on;
    }
  }

  Color _colourForModes(Set<String> modes) {
    if (modes.length > 1) {
      return const Color(0xFFF57C00);
    }

    if (modes.isEmpty) {
      return AppTheme.primaryBlue;
    }

    switch (modes.first) {
      case 'Bus':
        return AppTheme.primaryBlue;
      case 'Ferry':
        return const Color(0xFF00897B);
      case 'KTM':
      case 'MRT':
      case 'LRT':
      case 'Monorail':
        return const Color(0xFF7B1FA2);
      default:
        return AppTheme.primaryBlue;
    }
  }

  String _stationType(Set<String> modes) {
    if (modes.isEmpty) {
      return 'Transport stop';
    }

    switch (modes.first) {
      case 'Bus':
        return 'Bus stop';
      case 'Ferry':
        return 'Ferry terminal';
      case 'KTM':
      case 'MRT':
      case 'LRT':
      case 'Monorail':
        return '${modes.first} station';
      default:
        return 'Transport stop';
    }
  }

  Color _routeColour(String hexadecimalColour) {
    final value = hexadecimalColour.replaceFirst('#', '');

    return Color(int.parse('FF$value', radix: 16));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class CurrentUserLocationMarker extends StatelessWidget {
  const CurrentUserLocationMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.20),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
          ),
        ),
      ],
    );
  }
}
