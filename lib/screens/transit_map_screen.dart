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
  const TransitMapScreen({super.key});

  @override
  State<TransitMapScreen> createState() => _TransitMapScreenState();
}

class _TransitMapScreenState extends State<TransitMapScreen> {
  final TransitRepository _repository = TransitRepository.instance;
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final Location _location = Location();

  StreamSubscription<LocationData>? _locationSubscription;
  LocationData? _currentLocation;

  bool _loading = true;
  bool _trackingLocation = false;
  bool _requestingLocation = false;
  bool _followUserLocation = true;

  String? _error;
  String _selectedMode = 'All';

  TransitStop? _selectedStop;
  TransitRoute? _selectedRoute;

  List<TransitStop> _stopSuggestions = [];
  List<TransitRoute> _routeSuggestions = [];
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
    _loadTransitData();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _searchCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadTransitData() async {
    try {
      await _repository.load();

      if (!mounted) return;

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
      return _repository.routes;
    }

    return _repository.routes.where((route) {
      return route.mode == _selectedMode;
    }).toList();
  }

  List<TransitRoute> get _displayedRoutes {
    if (_selectedRoute != null) {
      return [_selectedRoute!];
    }

    return _filteredRoutes;
  }

  List<TransitStop> get _visibleStops {
    final stopIds = _displayedRoutes.expand((route) => route.stopIds).toSet();

    return _repository.stops.where((stop) {
      return stopIds.contains(stop.id);
    }).toList();
  }

  List<TransitRoute> _routesForStop(TransitStop stop) {
    return _repository.routes.where((route) {
      return route.stopIds.contains(stop.id);
    }).toList();
  }

  void _selectMode(String mode) {
    setState(() {
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
  }

  void _onSearchChanged(String value) {
    final query = value.trim();

    if (query.isEmpty || _loading) {
      setState(() {
        _stopSuggestions = [];
        _routeSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    final stops = _repository.searchStops(query, limit: 5);
    final routes = _repository.searchRoutes(query: query, mode: _selectedMode);

    setState(() {
      _stopSuggestions = stops;
      _routeSuggestions = routes.take(5).toList();
      _showSuggestions =
          _stopSuggestions.isNotEmpty || _routeSuggestions.isNotEmpty;
    });
  }

  void _selectStopSuggestion(TransitStop stop) {
    FocusScope.of(context).unfocus();

    setState(() {
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

    if (_stopSuggestions.isNotEmpty) {
      _selectStopSuggestion(_stopSuggestions.first);
      return;
    }

    if (_routeSuggestions.isNotEmpty) {
      _selectRouteSuggestion(_routeSuggestions.first);
      return;
    }

    final matchingStops = _repository.searchStops(query, limit: 1);

    if (matchingStops.isNotEmpty) {
      _selectStopSuggestion(matchingStops.first);
      return;
    }

    final matchingRoutes = _repository.searchRoutes(
      query: query,
      mode: _selectedMode,
    );

    if (matchingRoutes.isNotEmpty) {
      _selectRouteSuggestion(matchingRoutes.first);
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _showSuggestions = false;
    });

    _showMessage('No matching station, stop, or route found.');
  }

  void _showRoute(TransitRoute route) {
    final stops = _repository.stopsForRoute(route);

    setState(() {
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
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            onTap: () {
              if (_searchCtrl.text.trim().isNotEmpty) {
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
                        _searchCtrl.clear();

                        setState(() {
                          _stopSuggestions = [];
                          _routeSuggestions = [];
                          _showSuggestions = false;
                        });
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
          options: const MapOptions(
            initialCenter: LatLng(5.4145, 100.3292),
            initialZoom: 11,
            minZoom: 5,
            maxZoom: 19,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName:
                  'my.edu.tarumt.smart_tublic_transport_system',
              maxZoom: 19,
            ),
            PolylineLayer(polylines: _buildRoutePolylines()),
            MarkerLayer(markers: _visibleStops.map(_buildStopMarker).toList()),
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
      ],
    );
  }

  List<Polyline> _buildRoutePolylines() {
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
                  : route == null
                  ? '${_visibleStops.length} supported stops'
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
