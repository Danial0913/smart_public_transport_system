import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

import '../data/transit_repository.dart';
import '../models/transit_models.dart';
import '../theme/app_theme.dart';

class TransitMapScreen extends StatefulWidget {
  const TransitMapScreen({super.key, this.journey});

  final JourneyOption? journey;

  @override
  State<TransitMapScreen> createState() => _TransitMapScreenState();
}

class _TransitMapScreenState extends State<TransitMapScreen> {
  final TransitRepository _repository = TransitRepository.instance;
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final Location _location = Location();
  final ValueNotifier<int> _searchVersion = ValueNotifier<int>(0);
  final RegExp _searchSpaces = RegExp(r'\s+');

  StreamSubscription<LocationData>? _locationSubscription;
  Timer? _searchDebounce;
  Timer? _mapCameraDebounce;
  LocationData? _currentLocation;
  LatLngBounds? _visibleMapBounds;
  double _mapZoom = 11;

  bool _loading = true;
  bool _trackingLocation = false;
  bool _requestingLocation = false;
  bool _followUserLocation = true;

  String? _error;
  String _selectedMode = 'All';

  TransitStop? _selectedStop;
  TransitRoute? _selectedRoute;
  JourneyOption? _activeJourney;
  bool _mapReady = false;

  List<TransitStop> _stopSuggestions = [];
  List<TransitRoute> _routeSuggestions = [];
  List<TransitStop> _allStops = [];
  List<TransitRoute> _allRoutes = [];
  final Map<String, List<TransitRoute>> _routesByStopId = {};
  final Map<String, String> _normalisedStopNames = {};
  final Map<String, String> _normalisedRouteNames = {};
  bool _showSuggestions = false;

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
    _loadTransitData();
  }

  @override
  void didUpdateWidget(covariant TransitMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final journey = widget.journey;
    if (journey == null || oldWidget.journey?.id == journey.id) return;

    setState(() {
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
      await _repository.load();

      if (!mounted) return;

      _allStops = _repository.stops;
      _allRoutes = _repository.routes;
      _routesByStopId.clear();
      _normalisedStopNames.clear();
      _normalisedRouteNames.clear();

      for (final stop in _allStops) {
        _normalisedStopNames[stop.id] = _normaliseSearch(stop.name);
      }

      for (final route in _allRoutes) {
        _normalisedRouteNames[route.id] = _normaliseSearch(
          '${route.number} ${route.name}',
        );

        for (final stopId in route.stopIds) {
          _routesByStopId.putIfAbsent(stopId, () => []).add(route);
        }
      }

      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
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

  List<TransitStop> get _visibleStops {
    final journey = _activeJourney;
    if (journey != null) {
      final stopsById = <String, TransitStop>{};
      for (final leg in journey.legs) {
        for (final stop in leg.stops) {
          stopsById[stop.id] = stop;
        }
      }
      return stopsById.values.toList();
    }

    final stopIds = _displayedRoutes.expand((route) => route.stopIds).toSet();

    return _allStops.where((stop) {
      return stopIds.contains(stop.id);
    }).toList();
  }

  List<TransitStop> get _renderedStops {
    if (_activeJourney != null) {
      return _visibleStops;
    }

    if (_selectedRoute != null) {
      return _repository.stopsForRoute(_selectedRoute!);
    }

    final bounds = _visibleMapBounds;
    if (bounds == null || _mapZoom < 8.5) {
      return _selectedStop == null ? [] : [_selectedStop!];
    }

    final maximumMarkers = _mapZoom < 10
        ? 250
        : _mapZoom < 12
        ? 600
        : 1200;
    final stops = <TransitStop>[];

    for (final stop in _visibleStops) {
      if (bounds.contains(LatLng(stop.latitude, stop.longitude))) {
        stops.add(stop);
        if (stops.length == maximumMarkers) break;
      }
    }

    final selectedStop = _selectedStop;
    if (selectedStop != null &&
        !stops.any((stop) => stop.id == selectedStop.id)) {
      stops.add(selectedStop);
    }

    return stops;
  }

  List<TransitRoute> _routesForStop(TransitStop stop) {
    return _routesByStopId[stop.id] ?? const <TransitRoute>[];
  }

  void _selectMode(String mode) {
    setState(() {
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

  void _onMapReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _mapReady = true;
      final camera = _mapController.camera;
      setState(() {
        _visibleMapBounds = camera.visibleBounds;
        _mapZoom = camera.zoom;
      });

      final journey = _activeJourney;
      if (journey != null) {
        _focusJourney(journey);
      }
    });
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    _mapCameraDebounce?.cancel();
    _mapCameraDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;

      setState(() {
        _visibleMapBounds = camera.visibleBounds;
        _mapZoom = camera.zoom;
      });
    });
  }

  void _focusJourney(JourneyOption journey) {
    final points = <LatLng>[
      LatLng(journey.origin.latitude, journey.origin.longitude),
      for (final leg in journey.legs)
        for (final stop in leg.stops) LatLng(stop.latitude, stop.longitude),
      LatLng(journey.destination.latitude, journey.destination.longitude),
    ];

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(40, 70, 40, 190),
        maxZoom: 15,
      ),
    );
  }

  void _selectStopSuggestion(TransitStop stop) {
    FocusScope.of(context).unfocus();

    setState(() {
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

  void _showRoute(TransitRoute route) {
    final stops = _repository.stopsForRoute(route);

    setState(() {
      _activeJourney = null;
      _selectedRoute = route;
      _selectedStop = null;
      _selectedMode = route.mode;
    });

    if (stops.isNotEmpty) {
      final firstStop = stops.first;

      _mapController.move(LatLng(firstStop.latitude, firstStop.longitude), 11);
    }
  }

  void _showAllRoutes() {
    setState(() {
      _activeJourney = null;
      _selectedRoute = null;
      _selectedStop = null;
    });
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
        interval: 1000,
        distanceFilter: 5,
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

    if (latitude == null || longitude == null) return;

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
                selectedColor: AppTheme.primaryBlue.withOpacity(0.15),
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
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName:
                  'my.edu.tarumt.smart_tublic_transport_system',
              maxZoom: 19,
            ),
            PolylineLayer(polylines: _buildRoutePolylines()),
            MarkerLayer(markers: _renderedStops.map(_buildStopMarker).toList()),
            MarkerLayer(markers: _buildJourneyEndpointMarkers()),
            MarkerLayer(markers: _buildCurrentLocationMarkers()),
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
        if (_selectedStop != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildStopInformation(_selectedStop!),
          ),
        if (_selectedStop == null && _selectedRoute != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildRouteInformation(_selectedRoute!),
          ),
        if (_selectedStop == null &&
            _selectedRoute == null &&
            _activeJourney != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildJourneyInformation(_activeJourney!),
          ),
      ],
    );
  }

  List<Polyline> _buildRoutePolylines() {
    final journey = _activeJourney;
    if (journey != null) {
      return journey.legs.map((leg) {
        return Polyline(
          points: leg.stops.map((stop) {
            return LatLng(stop.latitude, stop.longitude);
          }).toList(),
          color: _routeColour(leg.route.colourHex),
          strokeWidth: 6,
        );
      }).toList();
    }

    return _displayedRoutes.map((route) {
      final stops = _repository.stopsForRoute(route);

      return Polyline(
        points: stops.map((stop) {
          return LatLng(stop.latitude, stop.longitude);
        }).toList(),
        color: _routeColour(
          route.colourHex,
        ).withOpacity(_selectedRoute == null ? 0.65 : 1),
        strokeWidth: _selectedRoute == null ? 4 : 6,
      );
    }).toList();
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
                  ? _mapZoom < 8.5
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

  Widget _buildJourneyInformation(JourneyOption journey) {
    return Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.navigation,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${journey.origin.name} to ${journey.destination.name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.mainText,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        journey.routeSummary,
                        style: const TextStyle(color: AppTheme.secondaryText),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close journey',
                  onPressed: () {
                    setState(() {
                      _activeJourney = null;
                    });
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildRouteSummary(
                    'Duration',
                    '${journey.totalDurationMinutes} min',
                    Icons.schedule,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildRouteSummary(
                    'Fare',
                    'RM${journey.totalFare.toStringAsFixed(2)}',
                    Icons.payments_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildRouteSummary(
                    'Transfers',
                    '${journey.transferCount}',
                    Icons.transfer_within_a_station,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _focusJourney(journey),
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('Show Entire Journey'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopInformation(TransitStop stop) {
    final routes = _routesForStop(stop);
    final modes = routes.map((route) => route.mode).toSet();

    return Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _colourForModes(modes).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconForModes(modes),
                    color: _colourForModes(modes),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stop.name,
                    style: const TextStyle(
                      color: AppTheme.mainText,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () {
                    setState(() {
                      _selectedStop = null;
                    });
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              Icons.category_outlined,
              'Type',
              modes.length > 1 ? 'Transport interchange' : _stationType(modes),
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.route,
              'Routes',
              routes.map((route) => route.number).join(', '),
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.accessible,
              'Accessible',
              stop.accessible ? 'Yes' : 'No',
            ),
            const SizedBox(height: 12),
            const Text(
              'Select a route',
              style: TextStyle(
                color: AppTheme.mainText,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: routes.map((route) {
                return ActionChip(
                  avatar: Icon(
                    _iconForMode(route.mode),
                    size: 18,
                    color: _routeColour(route.colourHex),
                  ),
                  label: Text(route.number),
                  onPressed: () => _showRoute(route),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteInformation(TransitRoute route) {
    final stops = _repository.stopsForRoute(route);

    return Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _routeColour(route.colourHex).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconForMode(route.mode),
                    color: _routeColour(route.colourHex),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${route.mode} ${route.number}',
                        style: const TextStyle(
                          color: AppTheme.mainText,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        route.name,
                        style: const TextStyle(color: AppTheme.secondaryText),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close route',
                  onPressed: _showAllRoutes,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildRouteSummary(
                    'Stops',
                    '${stops.length}',
                    Icons.location_on_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildRouteSummary(
                    'Fare',
                    'RM${route.baseFare.toStringAsFixed(2)}',
                    Icons.payments_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildRouteSummary(
                    'Frequency',
                    '${route.frequencyMinutes} min',
                    Icons.schedule,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: AppTheme.primaryBlue),
        const SizedBox(width: 9),
        SizedBox(
          width: 78,
          child: Text(
            title,
            style: const TextStyle(color: AppTheme.secondaryText),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppTheme.mainText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteSummary(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryBlue),
          const SizedBox(height: 5),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.mainText,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11),
          ),
        ],
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
            color: AppTheme.primaryBlue.withOpacity(0.20),
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
