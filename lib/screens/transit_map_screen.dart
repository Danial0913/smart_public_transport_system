import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

import '../data/transit_repository.dart';
import '../models/transit_models.dart';

class TransitMapScreen extends StatefulWidget {
  const TransitMapScreen({super.key, this.journey});

  // Journey received from Module 3
  final JourneyOption? journey;

  @override
  State<TransitMapScreen> createState() => _TransitMapScreenState();
}

class _TransitMapScreenState extends State<TransitMapScreen> {
  // Controllers
  final MapController _mapCtrl = MapController();
  final TextEditingController _searchCtrl = TextEditingController();

  // Services
  final TransitRepository _repository = TransitRepository.instance;
  final Location _location = Location();

  // Timers and subscriptions
  Timer? _searchTimer;
  Timer? _mapTimer;
  StreamSubscription<LocationData>? _locationSubscription;

  // Search update controller
  final ValueNotifier<int> _searchVersion = ValueNotifier<int>(0);

  // Transit data
  List<TransitStop> _allStops = [];
  List<TransitRoute> _allRoutes = [];

  // Search results
  List<TransitStop> _stopSuggestions = [];
  List<TransitRoute> _routeSuggestions = [];

  // Cached search data
  final Map<String, String> _stopSearchNames = {};
  final Map<String, String> _routeSearchNames = {};
  final Map<String, List<TransitRoute>> _routesByStopId = {};
  final Map<String, Set<String>> _stopIdsByMode = {};

  // Selected information
  TransitStop? _selectedStop;
  TransitRoute? _selectedRoute;
  JourneyOption? _activeJourney;

  // Map information
  LatLngBounds? _visibleBounds;
  double _mapZoom = 11;
  bool _mapReady = false;

  // Location information
  LocationData? _currentLocation;
  bool _trackingLocation = false;
  bool _requestingLocation = false;
  bool _followUserLocation = false;

  // Screen status
  bool _loading = true;
  bool _showSuggestions = false;
  String? _error;
  String _selectedMode = 'All';

  // Transport modes
  final List<String> _transportModes = const [
    'All',
    'Bus',
    'Ferry',
    'KTM',
    'MRT',
    'LRT',
    'Monorail',
  ];

  // Initialise the screen
  @override
  void initState() {
    super.initState();

    _activeJourney = widget.journey;
    _loadTransitData();
  }

  // Receive a new journey from Module 3
  @override
  void didUpdateWidget(covariant TransitMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newJourney = widget.journey;

    if (newJourney == null) return;
    if (newJourney.id == oldWidget.journey?.id) return;

    setState(() {
      _activeJourney = newJourney;
      _selectedStop = null;
      _selectedRoute = null;
      _selectedMode = 'All';
      _followUserLocation = false;
    });

    if (_mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showJourney(newJourney);
        }
      });
    }
  }

  // Dispose all controllers
  @override
  void dispose() {
    _searchTimer?.cancel();
    _mapTimer?.cancel();
    _locationSubscription?.cancel();

    _searchVersion.dispose();
    _searchCtrl.dispose();
    _mapCtrl.dispose();

    super.dispose();
  }

  // Load station, stop, and route data
  Future<void> _loadTransitData() async {
    try {
      await _repository.load();

      if (!mounted) return;

      _allStops = _repository.stops;
      _allRoutes = _repository.routes;

      // Prepare stop search names
      for (final stop in _allStops) {
        _stopSearchNames[stop.id] = _normalise(stop.name);
      }

      // Prepare route search names
      for (final route in _allRoutes) {
        _routeSearchNames[route.id] = _normalise(
          '${route.mode} ${route.number} ${route.name}',
        );

        // Connect stops with their routes
        for (final stopId in route.stopIds) {
          _routesByStopId.putIfAbsent(stopId, () => []).add(route);
        }

        // Store stop IDs based on transport mode
        _stopIdsByMode
            .putIfAbsent(route.mode, () => <String>{})
            .addAll(route.stopIds);
      }

      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  // Get routes based on transport mode
  List<TransitRoute> get _filteredRoutes {
    if (_selectedMode == 'All') {
      return _allRoutes;
    }

    return _allRoutes.where((route) {
      return route.mode == _selectedMode;
    }).toList();
  }

  // Get routes that should be displayed
  List<TransitRoute> get _displayedRoutes {
    final journey = _activeJourney;

    // Only show journey routes
    if (journey != null) {
      final routes = <String, TransitRoute>{};

      for (final leg in journey.legs) {
        routes[leg.route.id] = leg.route;
      }

      return routes.values.toList();
    }

    // Only show selected route
    if (_selectedRoute != null) {
      return [_selectedRoute!];
    }

    // Show routes based on transport filter
    return _filteredRoutes;
  }

  // Get stops that should be rendered
  List<TransitStop> get _renderedStops {
    // Journey stations use separate markers
    if (_activeJourney != null) {
      return [];
    }

    // Display every stop for one selected route
    if (_selectedRoute != null) {
      return _repository.stopsForRoute(_selectedRoute!);
    }

    final bounds = _visibleBounds;

    // Hide markers when the map is too far away
    if (bounds == null || _mapZoom < 8.5) {
      if (_selectedStop != null) {
        return [_selectedStop!];
      }

      return [];
    }

    // Get stops based on selected transport mode
    final allowedStopIds = _selectedMode == 'All'
        ? null
        : _stopIdsByMode[_selectedMode];

    // Limit marker count to prevent lag
    final maximumMarkers = _mapZoom < 10
        ? 250
        : _mapZoom < 12
        ? 600
        : 1200;

    final stops = <TransitStop>[];

    for (final stop in _allStops) {
      if (allowedStopIds != null && !allowedStopIds.contains(stop.id)) {
        continue;
      }

      final point = LatLng(stop.latitude, stop.longitude);

      if (bounds.contains(point)) {
        stops.add(stop);

        if (stops.length >= maximumMarkers) {
          break;
        }
      }
    }

    // Always include selected stop
    final selectedStop = _selectedStop;

    if (selectedStop != null &&
        !stops.any((stop) => stop.id == selectedStop.id)) {
      stops.add(selectedStop);
    }

    return stops;
  }

  // Get routes for one stop
  List<TransitRoute> _routesForStop(TransitStop stop) {
    return _routesByStopId[stop.id] ?? [];
  }

  // Select transport mode
  void _selectMode(String mode) {
    setState(() {
      _selectedMode = mode;
      _selectedStop = null;
      _selectedRoute = null;
      _activeJourney = null;
      _followUserLocation = false;
    });

    if (mode == 'All') {
      _mapCtrl.move(const LatLng(4.20, 101.50), 6);
    } else {
      final routes = _filteredRoutes;

      if (routes.isNotEmpty) {
        final stops = _repository.stopsForRoute(routes.first);

        if (stops.isNotEmpty) {
          _mapCtrl.move(
            LatLng(stops.first.latitude, stops.first.longitude),
            10,
          );
        }
      }
    }

    if (_searchCtrl.text.trim().length >= 2) {
      _onSearchChanged(_searchCtrl.text);
    }
  }

  // Detect search text changes
  void _onSearchChanged(String value) {
    _searchTimer?.cancel();

    final query = _normalise(value);

    if (query.length < 2 || _loading) {
      _clearSuggestions();
      return;
    }

    // Hide old suggestions while searching
    _showSuggestions = false;
    _searchVersion.value++;

    // Wait briefly before starting the search
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      final currentQuery = _normalise(_searchCtrl.text);

      if (currentQuery != query) return;

      _updateSuggestions(query);
    });
  }

  // Update search suggestions
  void _updateSuggestions(String query) {
    _stopSuggestions = _findStopSuggestions(query);
    _routeSuggestions = _findRouteSuggestions(query);

    _showSuggestions =
        _stopSuggestions.isNotEmpty || _routeSuggestions.isNotEmpty;

    _searchVersion.value++;
  }

  // Find stop suggestions
  List<TransitStop> _findStopSuggestions(String query) {
    final matches = <TransitStop>[];

    // Show names that start with the query first
    for (final stop in _allStops) {
      final name = _stopSearchNames[stop.id] ?? '';

      if (name.startsWith(query)) {
        matches.add(stop);

        if (matches.length == 5) {
          return matches;
        }
      }
    }

    // Show names that contain the query
    for (final stop in _allStops) {
      final name = _stopSearchNames[stop.id] ?? '';

      if (!name.startsWith(query) && name.contains(query)) {
        matches.add(stop);

        if (matches.length == 5) {
          break;
        }
      }
    }

    return matches;
  }

  // Find route suggestions
  List<TransitRoute> _findRouteSuggestions(String query) {
    final matches = <TransitRoute>[];

    // Show routes that start with the query
    for (final route in _allRoutes) {
      if (_selectedMode != 'All' && route.mode != _selectedMode) {
        continue;
      }

      final name = _routeSearchNames[route.id] ?? '';

      if (name.startsWith(query)) {
        matches.add(route);

        if (matches.length == 5) {
          return matches;
        }
      }
    }

    // Show routes that contain the query
    for (final route in _allRoutes) {
      if (_selectedMode != 'All' && route.mode != _selectedMode) {
        continue;
      }

      final name = _routeSearchNames[route.id] ?? '';

      if (!name.startsWith(query) && name.contains(query)) {
        matches.add(route);

        if (matches.length == 5) {
          break;
        }
      }
    }

    return matches;
  }

  // Convert search text into standard format
  String _normalise(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  // Clear search suggestions
  void _clearSuggestions() {
    _stopSuggestions = [];
    _routeSuggestions = [];
    _showSuggestions = false;

    _searchVersion.value++;
  }

  // Select stop suggestion
  void _selectStop(TransitStop stop) {
    FocusScope.of(context).unfocus();

    setState(() {
      _searchCtrl.text = stop.name;
      _selectedStop = stop;
      _selectedRoute = null;
      _activeJourney = null;
      _followUserLocation = false;
    });

    _clearSuggestions();

    _mapCtrl.move(LatLng(stop.latitude, stop.longitude), 14);
  }

  // Select route suggestion
  void _selectRoute(TransitRoute route) {
    FocusScope.of(context).unfocus();

    _searchCtrl.text = '${route.mode} ${route.number}';

    _clearSuggestions();
    _showRoute(route);
  }

  // Search button function
  void _search() {
    final query = _normalise(_searchCtrl.text);

    if (query.isEmpty) {
      _showMessage('Enter a station, stop, or route name.');
      return;
    }

    _searchTimer?.cancel();
    _updateSuggestions(query);

    if (_stopSuggestions.isNotEmpty) {
      _selectStop(_stopSuggestions.first);
      return;
    }

    if (_routeSuggestions.isNotEmpty) {
      _selectRoute(_routeSuggestions.first);
      return;
    }

    FocusScope.of(context).unfocus();
    _clearSuggestions();

    _showMessage('No matching station, stop, or route found.');
  }

  // Show one selected route
  void _showRoute(TransitRoute route) {
    final stops = _repository.stopsForRoute(route);

    setState(() {
      _selectedRoute = route;
      _selectedStop = null;
      _selectedMode = route.mode;
      _activeJourney = null;
      _followUserLocation = false;
    });

    if (stops.isEmpty) return;

    final points = stops.map((stop) {
      return LatLng(stop.latitude, stop.longitude);
    }).toList();

    if (points.length == 1) {
      _mapCtrl.move(points.first, 14);
      return;
    }

    _mapCtrl.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(50),
        maxZoom: 15,
      ),
    );
  }

  // Show all routes again
  void _showAllRoutes() {
    setState(() {
      _selectedStop = null;
      _selectedRoute = null;
      _activeJourney = null;
    });
  }

  // Run when map is ready
  void _onMapReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final camera = _mapCtrl.camera;

      setState(() {
        _mapReady = true;
        _visibleBounds = camera.visibleBounds;
        _mapZoom = camera.zoom;
      });

      final journey = _activeJourney;

      if (journey != null) {
        _showJourney(journey);
      }
    });
  }

  // Detect map movement
  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    _mapTimer?.cancel();

    if (hasGesture) {
      _followUserLocation = false;
    }

    _mapTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;

      setState(() {
        _visibleBounds = camera.visibleBounds;
        _mapZoom = camera.zoom;
      });
    });
  }

  // Show the complete journey
  void _showJourney(JourneyOption journey) {
    if (journey.legs.isEmpty) return;

    final points = <LatLng>[
      LatLng(journey.origin.latitude, journey.origin.longitude),
      for (final leg in journey.legs)
        for (final stop in leg.stops) LatLng(stop.latitude, stop.longitude),
      LatLng(journey.destination.latitude, journey.destination.longitude),
    ];

    _mapCtrl.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(40, 70, 40, 190),
        maxZoom: 15,
      ),
    );
  }

  // Check location permission and GPS
  Future<bool> _prepareLocationService() async {
    final permission = await handler.Permission.locationWhenInUse.request();

    if (permission != handler.PermissionStatus.granted) {
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
        _showMessage('Please enable GPS.');
      }

      return false;
    }

    return true;
  }

  // Start live location tracking
  Future<void> _startLocationTracking() async {
    if (_trackingLocation || _requestingLocation) {
      return;
    }

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

      final location = await _location.getLocation();

      if (!mounted) return;

      _updateLocation(location);

      await _locationSubscription?.cancel();

      _locationSubscription = _location.onLocationChanged.listen(
        _updateLocation,
        onError: (Object error) {
          if (mounted) {
            _showMessage('Location error: $error');
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
        _showMessage('Unable to start location tracking.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _requestingLocation = false;
        });
      }
    }
  }

  // Update current location
  void _updateLocation(LocationData location) {
    final latitude = location.latitude;
    final longitude = location.longitude;

    if (!mounted || latitude == null || longitude == null) {
      return;
    }

    setState(() {
      _currentLocation = location;
    });

    if (_followUserLocation) {
      _mapCtrl.move(LatLng(latitude, longitude), 15);
    }
  }

  // Stop live location tracking
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

  // Move map to current location
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

    _mapCtrl.move(LatLng(latitude, longitude), 15);
  }

  // Build the screen
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearch(),
        _buildFilters(),
        Expanded(child: _buildMap()),
      ],
    );
  }

  // Build search function
  Widget _buildSearch() {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: ValueListenableBuilder<int>(
          valueListenable: _searchVersion,
          builder: (context, version, child) {
            return Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _search(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search station, stop, or route',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchCtrl.text.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              _searchTimer?.cancel();
                              _searchCtrl.clear();
                              _clearSuggestions();
                            },
                            icon: const Icon(Icons.close),
                          ),
                        IconButton(
                          onPressed: _search,
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_showSuggestions) _buildSuggestions(),
              ],
            );
          },
        ),
      ),
    );
  }

  // Build search suggestion dropdown
  Widget _buildSuggestions() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          // Stop suggestions
          ..._stopSuggestions.map((stop) {
            final routes = _routesForStop(stop);
            final modes = routes.map((route) => route.mode).toSet();

            return ListTile(
              dense: true,
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
                routes.isEmpty
                    ? 'Transport stop'
                    : routes.map((route) => route.number).take(5).join(', '),
              ),
              onTap: () => _selectStop(stop),
            );
          }),

          // Route suggestions
          ..._routeSuggestions.map((route) {
            return ListTile(
              dense: true,
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
              onTap: () => _selectRoute(route),
            );
          }),
        ],
      ),
    );
  }

  // Build transport mode filters
  Widget _buildFilters() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _transportModes.map((mode) {
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(mode),
                selected: _selectedMode == mode,
                onSelected: (_) {
                  _selectMode(mode);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Build map section
  Widget _buildMap() {
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
              const SizedBox(height: 10),
              const Text(
                'Unable to load transit data',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
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
        // OpenStreetMap
        FlutterMap(
          mapController: _mapCtrl,
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

            // Route lines
            PolylineLayer(polylines: _buildRouteLines()),

            // Station and stop markers
            MarkerLayer(markers: _renderedStops.map(_buildStopMarker).toList()),

            // Journey markers
            MarkerLayer(markers: _buildJourneyMarkers()),

            // User location marker
            MarkerLayer(markers: _buildLocationMarker()),

            // OpenStreetMap credit
            const Align(
              alignment: Alignment.topRight,
              child: ColoredBox(
                color: Colors.white70,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(fontSize: 9),
                  ),
                ),
              ),
            ),
          ],
        ),

        // Map status
        Positioned(left: 10, top: 10, child: _buildMapStatus()),

        // Map control buttons
        Positioned(
          right: 10,
          top: 38,
          child: Column(
            children: [
              _buildMapButton(
                tooltip: 'Show Penang',
                icon: Icons.location_city,
                onPressed: () {
                  _followUserLocation = false;

                  _mapCtrl.move(const LatLng(5.4145, 100.3292), 11);
                },
              ),
              const SizedBox(height: 7),
              _buildMapButton(
                tooltip: 'Show Malaysia',
                icon: Icons.public,
                onPressed: () {
                  _followUserLocation = false;

                  _mapCtrl.move(const LatLng(4.20, 101.50), 6);
                },
              ),
              const SizedBox(height: 7),
              _buildMapButton(
                tooltip: _trackingLocation ? 'Stop tracking' : 'Start tracking',
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
                const SizedBox(height: 7),
                _buildMapButton(
                  tooltip: 'My location',
                  icon: Icons.gps_fixed,
                  onPressed: _moveToCurrentLocation,
                ),
              ],
              if (_selectedRoute != null || _activeJourney != null) ...[
                const SizedBox(height: 7),
                _buildMapButton(
                  tooltip: 'Show all routes',
                  icon: Icons.layers,
                  onPressed: _showAllRoutes,
                ),
              ],
            ],
          ),
        ),

        // Selected information
        if (_selectedStop != null)
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: _buildStopCard(_selectedStop!),
          )
        else if (_selectedRoute != null)
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: _buildRouteCard(_selectedRoute!),
          )
        else if (_activeJourney != null)
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: _buildJourneyCard(_activeJourney!),
          ),
      ],
    );
  }

  // Build route and walking lines
  List<Polyline> _buildRouteLines() {
    final journey = _activeJourney;

    // Display active journey lines
    if (journey != null && journey.legs.isNotEmpty) {
      final lines = <Polyline>[];

      final firstLeg = journey.legs.first;
      final lastLeg = journey.legs.last;

      // Walk from origin to first station
      _addWalkingLine(
        lines,
        LatLng(journey.origin.latitude, journey.origin.longitude),
        LatLng(firstLeg.from.latitude, firstLeg.from.longitude),
      );

      for (int index = 0; index < journey.legs.length; index++) {
        final leg = journey.legs[index];

        // Add transport route line
        lines.add(
          Polyline(
            points: leg.stops.map((stop) {
              return LatLng(stop.latitude, stop.longitude);
            }).toList(),
            color: _routeColour(leg.route.colourHex),
            strokeWidth: 6,
          ),
        );

        // Add walking transfer
        if (index < journey.legs.length - 1) {
          final nextLeg = journey.legs[index + 1];

          _addWalkingLine(
            lines,
            LatLng(leg.to.latitude, leg.to.longitude),
            LatLng(nextLeg.from.latitude, nextLeg.from.longitude),
          );
        }
      }

      // Walk from last station to destination
      _addWalkingLine(
        lines,
        LatLng(lastLeg.to.latitude, lastLeg.to.longitude),
        LatLng(journey.destination.latitude, journey.destination.longitude),
      );

      return lines;
    }

    // Display selected or filtered routes
    final lines = <Polyline>[];

    for (final route in _displayedRoutes) {
      final stops = _repository.stopsForRoute(route);

      if (stops.length < 2) continue;

      lines.add(
        Polyline(
          points: stops.map((stop) {
            return LatLng(stop.latitude, stop.longitude);
          }).toList(),
          color: _routeColour(
            route.colourHex,
          ).withOpacity(_selectedRoute == null ? 0.65 : 1),
          strokeWidth: _selectedRoute == null ? 4 : 6,
        ),
      );
    }

    return lines;
  }

  // Add walking line
  void _addWalkingLine(List<Polyline> lines, LatLng from, LatLng to) {
    final sameLocation =
        (from.latitude - to.latitude).abs() < 0.000001 &&
        (from.longitude - to.longitude).abs() < 0.000001;

    if (sameLocation) return;

    lines.add(
      Polyline(points: [from, to], color: Colors.grey.shade700, strokeWidth: 4),
    );
  }

  // Build stop marker
  Marker _buildStopMarker(TransitStop stop) {
    final routes = _routesForStop(stop);
    final modes = routes.map((route) => route.mode).toSet();

    final selected = _selectedStop?.id == stop.id;
    final colour = selected ? Colors.red : _colourForModes(modes);

    return Marker(
      point: LatLng(stop.latitude, stop.longitude),
      width: 44,
      height: 44,
      child: Tooltip(
        message: stop.name,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedStop = stop;
              _followUserLocation = false;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: colour, width: selected ? 4 : 3),
            ),
            child: Icon(_iconForModes(modes), color: colour, size: 23),
          ),
        ),
      ),
    );
  }

  // Build journey markers
  List<Marker> _buildJourneyMarkers() {
    final journey = _activeJourney;

    if (journey == null || journey.legs.isEmpty) {
      return [];
    }

    final markers = <Marker>[];

    // Journey origin
    markers.add(
      _buildSimpleMarker(
        point: LatLng(journey.origin.latitude, journey.origin.longitude),
        tooltip: 'Start: ${journey.origin.name}',
        icon: Icons.trip_origin,
        colour: Colors.green,
        filled: true,
      ),
    );

    // First boarding station
    final firstLeg = journey.legs.first;

    markers.add(
      _buildSimpleMarker(
        point: LatLng(firstLeg.from.latitude, firstLeg.from.longitude),
        tooltip: 'Board ${firstLeg.route.number} at ${firstLeg.from.name}',
        icon: _iconForMode(firstLeg.route.mode),
        colour: _routeColour(firstLeg.route.colourHex),
        onTap: () {
          setState(() {
            _selectedStop = firstLeg.from;
          });
        },
      ),
    );

    // Transfer stations
    for (int index = 0; index < journey.legs.length - 1; index++) {
      final currentLeg = journey.legs[index];
      final nextLeg = journey.legs[index + 1];

      markers.add(
        _buildSimpleMarker(
          point: LatLng(currentLeg.to.latitude, currentLeg.to.longitude),
          tooltip:
              'Change ${currentLeg.route.number} to '
              '${nextLeg.route.number} at ${currentLeg.to.name}',
          icon: Icons.transfer_within_a_station,
          colour: Colors.orange,
          onTap: () {
            setState(() {
              _selectedStop = currentLeg.to;
            });
          },
        ),
      );

      // Different transfer station requires walking
      if (currentLeg.to.id != nextLeg.from.id) {
        markers.add(
          _buildSimpleMarker(
            point: LatLng(nextLeg.from.latitude, nextLeg.from.longitude),
            tooltip:
                'Walk and board ${nextLeg.route.number} '
                'at ${nextLeg.from.name}',
            icon: Icons.directions_walk,
            colour: Colors.grey.shade700,
            onTap: () {
              setState(() {
                _selectedStop = nextLeg.from;
              });
            },
          ),
        );
      }
    }

    // Final alighting station
    final lastLeg = journey.legs.last;

    markers.add(
      _buildSimpleMarker(
        point: LatLng(lastLeg.to.latitude, lastLeg.to.longitude),
        tooltip: 'Leave ${lastLeg.route.number} at ${lastLeg.to.name}',
        icon: Icons.stop_circle_outlined,
        colour: _routeColour(lastLeg.route.colourHex),
        onTap: () {
          setState(() {
            _selectedStop = lastLeg.to;
          });
        },
      ),
    );

    // Journey destination
    markers.add(
      _buildSimpleMarker(
        point: LatLng(
          journey.destination.latitude,
          journey.destination.longitude,
        ),
        tooltip: 'Destination: ${journey.destination.name}',
        icon: Icons.flag,
        colour: Colors.red,
        filled: true,
      ),
    );

    return markers;
  }

  // Build reusable journey marker
  Marker _buildSimpleMarker({
    required LatLng point,
    required String tooltip,
    required IconData icon,
    required Color colour,
    VoidCallback? onTap,
    bool filled = false,
  }) {
    return Marker(
      point: point,
      width: 48,
      height: 48,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: filled ? colour : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: filled ? Colors.white : colour,
                width: 3,
              ),
            ),
            child: Icon(icon, color: filled ? Colors.white : colour, size: 25),
          ),
        ),
      ),
    );
  }

  // Build current location marker
  List<Marker> _buildLocationMarker() {
    final latitude = _currentLocation?.latitude;
    final longitude = _currentLocation?.longitude;

    if (latitude == null || longitude == null) {
      return [];
    }

    return [
      Marker(
        point: LatLng(latitude, longitude),
        width: 40,
        height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.25),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      ),
    ];
  }

  // Build map status
  Widget _buildMapStatus() {
    String text = '${_renderedStops.length} stops';

    if (_mapZoom < 8.5 && _selectedRoute == null && _activeJourney == null) {
      text = 'Zoom in to view stops';
    }

    if (_selectedRoute != null) {
      text = 'Route ${_selectedRoute!.number}';
    }

    if (_activeJourney != null) {
      text = 'Journey ${_activeJourney!.routeSummary}';
    }

    if (_trackingLocation) {
      text = 'Live location';
    }

    return Chip(
      avatar: Icon(
        _trackingLocation
            ? Icons.gps_fixed
            : _activeJourney != null
            ? Icons.navigation
            : Icons.map,
        size: 18,
        color: _trackingLocation ? Colors.green : Colors.blue,
      ),
      label: Text(text),
      backgroundColor: Colors.white,
    );
  }

  // Build reusable map button
  Widget _buildMapButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.white,
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: onPressed == null ? Colors.grey : Colors.blue),
      ),
    );
  }

  // Build selected stop information
  Widget _buildStopCard(TransitStop stop) {
    final routes = _routesForStop(stop);
    final modes = routes.map((route) => route.mode).toSet();

    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: _colourForModes(modes).withOpacity(0.15),
                child: Icon(
                  _iconForModes(modes),
                  color: _colourForModes(modes),
                ),
              ),
              title: Text(
                stop.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${_stationType(modes)} · '
                '${stop.accessible ? "Accessible" : "Not accessible"}',
              ),
              trailing: IconButton(
                onPressed: () {
                  setState(() {
                    _selectedStop = null;
                  });
                },
                icon: const Icon(Icons.close),
              ),
            ),

            // Available routes
            if (routes.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: routes.take(12).map((route) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          avatar: Icon(_iconForMode(route.mode), size: 17),
                          label: Text(route.number),
                          onPressed: () {
                            _showRoute(route);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Build selected route information
  Widget _buildRouteCard(TransitRoute route) {
    final stops = _repository.stopsForRoute(route);

    final firstStop = stops.isEmpty ? 'Unknown' : stops.first.name;

    final lastStop = stops.isEmpty ? 'Unknown' : stops.last.name;

    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: _routeColour(
                  route.colourHex,
                ).withOpacity(0.15),
                child: Icon(
                  _iconForMode(route.mode),
                  color: _routeColour(route.colourHex),
                ),
              ),
              title: Text(
                '${route.mode} ${route.number}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(route.name),
              trailing: IconButton(
                onPressed: _showAllRoutes,
                icon: const Icon(Icons.close),
              ),
            ),
            Text(
              '$firstStop → $lastStop',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('${stops.length} stops'),
                Text('RM${route.baseFare.toStringAsFixed(2)}'),
                Text('${route.frequencyMinutes} min'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Build active journey information
  Widget _buildJourneyCard(JourneyOption journey) {
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.navigation)),
              title: Text(
                '${journey.origin.name} to '
                '${journey.destination.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${journey.totalDurationMinutes} min · '
                'RM${journey.totalFare.toStringAsFixed(2)} · '
                '${journey.transferCount} transfer(s)',
              ),
              trailing: IconButton(
                onPressed: () {
                  setState(() {
                    _activeJourney = null;
                  });
                },
                icon: const Icon(Icons.close),
              ),
            ),

            // Walking and transport sequence
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _buildJourneySteps(journey)),
            ),

            const SizedBox(height: 8),

            // Show complete journey button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _showJourney(journey);
                },
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('Show Entire Journey'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build journey sequence
  List<Widget> _buildJourneySteps(JourneyOption journey) {
    final steps = <Widget>[];

    void addStep(Widget widget) {
      if (steps.isNotEmpty) {
        steps.add(const Icon(Icons.chevron_right, size: 20));
      }

      steps.add(widget);
    }

    // Walking from origin
    if (journey.originWalkingMetres > 0) {
      addStep(
        Chip(
          avatar: const Icon(Icons.directions_walk, size: 17),
          label: Text('${journey.originWalkingMetres} m'),
        ),
      );
    }

    // Transport legs
    for (int index = 0; index < journey.legs.length; index++) {
      final leg = journey.legs[index];

      addStep(
        Chip(
          avatar: Icon(
            _iconForMode(leg.route.mode),
            size: 17,
            color: _routeColour(leg.route.colourHex),
          ),
          label: Text(leg.route.number),
        ),
      );

      // Walking transfer
      if (index < journey.legs.length - 1) {
        final nextLeg = journey.legs[index + 1];

        if (leg.to.id != nextLeg.from.id) {
          addStep(
            const Chip(
              avatar: Icon(Icons.directions_walk, size: 17),
              label: Text('Walk'),
            ),
          );
        }
      }
    }

    // Walking to destination
    if (journey.destinationWalkingMetres > 0) {
      addStep(
        Chip(
          avatar: const Icon(Icons.directions_walk, size: 17),
          label: Text('${journey.destinationWalkingMetres} m'),
        ),
      );
    }

    return steps;
  }

  // Select icon for multiple modes
  IconData _iconForModes(Set<String> modes) {
    if (modes.length > 1) {
      return Icons.hub;
    }

    if (modes.isEmpty) {
      return Icons.location_on;
    }

    return _iconForMode(modes.first);
  }

  // Select transport mode icon
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

  // Select colour for transport modes
  Color _colourForModes(Set<String> modes) {
    if (modes.length > 1) {
      return Colors.orange;
    }

    if (modes.isEmpty) {
      return Colors.blue;
    }

    switch (modes.first) {
      case 'Bus':
        return Colors.blue;

      case 'Ferry':
        return Colors.teal;

      case 'KTM':
        return Colors.deepPurple;

      case 'MRT':
        return Colors.green;

      case 'LRT':
        return Colors.red;

      case 'Monorail':
        return Colors.orange;

      default:
        return Colors.blue;
    }
  }

  // Get station type
  String _stationType(Set<String> modes) {
    if (modes.length > 1) {
      return 'Transport interchange';
    }

    if (modes.isEmpty) {
      return 'Transport stop';
    }

    switch (modes.first) {
      case 'Bus':
        return 'Bus stop';

      case 'Ferry':
        return 'Ferry terminal';

      case 'KTM':
        return 'KTM station';

      case 'MRT':
        return 'MRT station';

      case 'LRT':
        return 'LRT station';

      case 'Monorail':
        return 'Monorail station';

      default:
        return 'Transport stop';
    }
  }

  // Convert route hexadecimal colour
  Color _routeColour(String hexadecimalColour) {
    try {
      var value = hexadecimalColour.replaceAll('#', '').trim();

      if (value.length == 6) {
        value = 'FF$value';
      }

      return Color(int.parse(value, radix: 16));
    } catch (_) {
      return Colors.blue;
    }
  }

  // Show message
  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
