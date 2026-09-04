import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/geocoding_service.dart';
import '../data/input_validator.dart';
import '../data/location_service.dart';
import '../data/transit_repository.dart';
import '../models/transit_models.dart';
import '../theme/app_theme.dart';

class SupportedStopMapPicker extends StatefulWidget {
  const SupportedStopMapPicker({
    super.key,
    required this.title,
    required this.stops,
    this.initialLocation,
  });

  final String title;
  final List<TransitStop> stops;
  final JourneyLocation? initialLocation;

  @override
  State<SupportedStopMapPicker> createState() => _SupportedStopMapPickerState();
}

class _SupportedStopMapPickerState extends State<SupportedStopMapPicker> {
  final GeocodingService _geocodingService = GeocodingService();
  final TransitRepository _repository = TransitRepository.instance;
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _mapMoveDebounce;
  LatLng? _selectedPoint;
  String? _selectedName;
  TransitStop? _nearestStop;
  List<TransitStop> _visibleMapStops = [];
  late List<TransitStop> _availableStops;
  bool _searching = false;
  bool _findingName = false;
  bool _loadingStops = false;

  @override
  void initState() {
    super.initState();
    _availableStops = List.of(widget.stops);
    final initialLocation = widget.initialLocation;
    if (initialLocation != null &&
        LocationService.isInsideMalaysia(
          initialLocation.latitude,
          initialLocation.longitude,
        )) {
      _selectedPoint = LatLng(
        initialLocation.latitude,
        initialLocation.longitude,
      );
      _selectedName = initialLocation.name;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final point = _selectedPoint;
      if (point != null) _loadStopsNear(point);
    });
  }

  @override
  void dispose() {
    _mapMoveDebounce?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _selectPoint(LatLng point, {String? name}) async {
    if (!LocationService.isInsideMalaysia(point.latitude, point.longitude)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location inside Malaysia.'),
        ),
      );
      return;
    }
    await _loadStopsNear(point);
    if (!mounted) return;
    final nearestStop = _findNearestStop(point);
    setState(() {
      _selectedPoint = point;
      _selectedName = name;
      _nearestStop = nearestStop;
      _findingName = name == null;
    });
    _refreshVisibleStops(_mapController.camera);

    if (name != null) return;

    final placeName = await _geocodingService.getPlaceName(
      point.latitude,
      point.longitude,
    );
    if (!mounted || _selectedPoint != point) return;

    setState(() {
      _selectedName =
          placeName ??
          (nearestStop == null
              ? 'Selected location'
              : 'Near ${nearestStop.name}');
      _findingName = false;
    });
  }

  Future<void> _searchForLocation() async {
    if (_searching) return;
    final query = _searchController.text.trim();
    final validationError = InputValidator.locationSearch(query);
    if (validationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }
    setState(() => _searching = true);

    final location = await _geocodingService.searchLocation(query);
    if (!mounted) return;

    setState(() => _searching = false);
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location not found. Try a more complete name.'),
        ),
      );
      return;
    }

    final point = LatLng(location.latitude, location.longitude);
    await _selectPoint(point, name: location.name);
    _mapController.move(point, 15);
  }

  TransitStop? _findNearestStop(LatLng point) {
    TransitStop? nearestStop;
    double? smallestDifference;

    for (final stop in _availableStops) {
      final latitudeDifference = stop.latitude - point.latitude;
      final longitudeDifference = stop.longitude - point.longitude;
      final difference =
          latitudeDifference * latitudeDifference +
          longitudeDifference * longitudeDifference;
      if (smallestDifference == null || difference < smallestDifference) {
        smallestDifference = difference;
        nearestStop = stop;
      }
    }
    return nearestStop;
  }

  void _onMapReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshVisibleStops(_mapController.camera);
    });
  }

  void _onMapPositionChanged(MapCamera camera, bool _) {
    _mapMoveDebounce?.cancel();
    _mapMoveDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _refreshVisibleStops(camera);
    });
  }

  Future<void> _loadStopsNear(LatLng point) async {
    if (_loadingStops) return;
    _loadingStops = true;
    try {
      await _repository.ensureDataNear(point.latitude, point.longitude);
      if (!mounted) return;
      setState(() => _availableStops = _repository.stops);
      _refreshVisibleStops(_mapController.camera);
    } catch (_) {
      // A place can still be selected when an official feed is unavailable.
    } finally {
      _loadingStops = false;
    }
  }

  void _refreshVisibleStops(MapCamera camera) {
    final selectedPoint = _selectedPoint;
    final zoom = camera.zoom;
    if (selectedPoint == null || zoom < 9) {
      if (_visibleMapStops.isEmpty) return;
      setState(() => _visibleMapStops = []);
      return;
    }

    final bounds = camera.visibleBounds;
    final visibleStops = _availableStops.where((stop) {
      if (!bounds.contains(LatLng(stop.latitude, stop.longitude))) return false;
      return _distanceSquared(
            stop.latitude,
            stop.longitude,
            selectedPoint.latitude,
            selectedPoint.longitude,
          ) <=
          0.0025;
    }).toList();
    visibleStops.sort((a, b) {
      final first = _distanceSquared(
        a.latitude,
        a.longitude,
        selectedPoint.latitude,
        selectedPoint.longitude,
      );
      final second = _distanceSquared(
        b.latitude,
        b.longitude,
        selectedPoint.latitude,
        selectedPoint.longitude,
      );
      return first.compareTo(second);
    });

    final nextStops = visibleStops.take(40).toList();
    if (_sameStops(_visibleMapStops, nextStops)) return;
    setState(() => _visibleMapStops = nextStops);
  }

  bool _sameStops(List<TransitStop> first, List<TransitStop> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index].id != second[index].id) return false;
    }
    return true;
  }

  double _distanceSquared(
    double firstLatitude,
    double firstLongitude,
    double secondLatitude,
    double secondLongitude,
  ) {
    final latitude = firstLatitude - secondLatitude;
    final longitude = firstLongitude - secondLongitude;
    return latitude * latitude + longitude * longitude;
  }

  void _returnSelectedLocation() {
    final point = _selectedPoint;
    if (point == null) return;

    final name = _selectedName ?? 'Selected location';
    Navigator.pop(
      context,
      JourneyLocation(
        name: name,
        latitude: point.latitude,
        longitude: point.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suppliedInitialLocation = widget.initialLocation;
    final initialLocation =
        suppliedInitialLocation != null &&
            LocationService.isInsideMalaysia(
              suppliedInitialLocation.latitude,
              suppliedInitialLocation.longitude,
            )
        ? suppliedInitialLocation
        : null;
    final initialCentre = initialLocation == null
        ? const LatLng(5.4145, 100.3292)
        : LatLng(initialLocation.latitude, initialLocation.longitude);
    final selectedPoint = _selectedPoint;
    final nearestStop = _nearestStop;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchForLocation(),
                    decoration: const InputDecoration(
                      hintText: 'Search place, address or landmark',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 48),
                  ),
                  onPressed: _searching ? null : _searchForLocation,
                  child: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Search'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: initialCentre,
                    initialZoom: initialLocation == null ? 11 : 14,
                    onMapReady: _onMapReady,
                    onPositionChanged: _onMapPositionChanged,
                    onTap: (_, point) async {
                      await _selectPoint(point);
                      if (mounted && _mapController.camera.zoom < 11) {
                        _mapController.move(point, 12);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      maxZoom: 19,
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'my.edu.tarumt.smart_public_transport_system',
                      panBuffer: 0,
                    ),
                    MarkerLayer(
                      markers: [
                        for (final stop in _visibleMapStops)
                          Marker(
                            width: 38,
                            height: 38,
                            point: LatLng(stop.latitude, stop.longitude),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _selectPoint(
                                LatLng(stop.latitude, stop.longitude),
                                name: stop.name,
                              ),
                              child: Tooltip(
                                message: stop.name,
                                child: const Icon(
                                  Icons.directions_transit,
                                  size: 25,
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                            ),
                          ),
                        if (selectedPoint != null)
                          Marker(
                            width: 48,
                            height: 48,
                            point: selectedPoint,
                            child: const Icon(
                              Icons.location_on,
                              size: 44,
                              color: Colors.red,
                            ),
                          ),
                      ],
                    ),
                    const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: ColoredBox(
                          color: Colors.white70,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
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
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.touch_app,
                            color: AppTheme.primaryBlue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: selectedPoint == null
                                ? const Text(
                                    'Tap a region to load nearby official stops.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _findingName
                                            ? 'Finding place name...'
                                            : _selectedName ??
                                                  'Selected location',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (nearestStop != null)
                                        Text(
                                          'Nearest transport stop: '
                                          '${nearestStop.name}',
                                          style: const TextStyle(
                                            color: AppTheme.secondaryText,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(84, 44),
                            ),
                            onPressed: selectedPoint == null || _findingName
                                ? null
                                : _returnSelectedLocation,
                            child: const Text('Select'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
