import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/location_service.dart';
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
  State<SupportedStopMapPicker> createState() =>
      _SupportedStopMapPickerState();
}

class _SupportedStopMapPickerState extends State<SupportedStopMapPicker> {
  LatLng? _selectedPoint;
  String? _selectedName;

  List<TransitStop> get _mapStops {
    const maximumMarkers = 500;
    if (widget.stops.length <= maximumMarkers) return widget.stops;

    final step = (widget.stops.length / maximumMarkers).ceil();
    final visibleStops = <TransitStop>[];
    for (var index = 0; index < widget.stops.length; index += step) {
      visibleStops.add(widget.stops[index]);
    }
    return visibleStops;
  }

  @override
  void initState() {
    super.initState();
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
  }

  void _selectPoint(LatLng point, {String? name}) {
    if (!LocationService.isInsideMalaysia(
      point.latitude,
      point.longitude,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location inside Malaysia.'),
        ),
      );
      return;
    }
    setState(() {
      _selectedPoint = point;
      _selectedName = name;
    });
  }

  TransitStop? _findNearestStop(LatLng point) {
    TransitStop? nearestStop;
    double? smallestDifference;

    for (final stop in widget.stops) {
      final latitudeDifference = stop.latitude - point.latitude;
      final longitudeDifference = stop.longitude - point.longitude;
      final difference = latitudeDifference * latitudeDifference +
          longitudeDifference * longitudeDifference;
      if (smallestDifference == null || difference < smallestDifference) {
        smallestDifference = difference;
        nearestStop = stop;
      }
    }
    return nearestStop;
  }

  void _returnSelectedLocation() {
    final point = _selectedPoint;
    if (point == null) return;

    final name = _selectedName ??
        'Map location (${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)})';
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
    final initialLocation = suppliedInitialLocation != null &&
            LocationService.isInsideMalaysia(
              suppliedInitialLocation.latitude,
              suppliedInitialLocation.longitude,
            )
        ? suppliedInitialLocation
        : null;
    final initialCentre = initialLocation == null
        ? const LatLng(5.4141, 100.3288)
        : LatLng(initialLocation.latitude, initialLocation.longitude);
    final selectedPoint = _selectedPoint;
    final nearestStop =
        selectedPoint == null ? null : _findNearestStop(selectedPoint);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.86,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Tap anywhere on the map to choose a location.',
                          style: TextStyle(
                            color: AppTheme.secondaryText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: initialCentre,
                      initialZoom: initialLocation == null ? 11 : 14,
                      onTap: (_, point) => _selectPoint(point),
                    ),
                    children: [
                      TileLayer(
                        maxZoom: 19,
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'my.edu.tarumt.smart_tublic_transport_system',
                      ),
                      MarkerLayer(
                        markers: [
                          for (final stop in _mapStops)
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
                                      'Tap the map to select a location.',
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
                                          _selectedName ?? 'Selected location',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '${selectedPoint.latitude.toStringAsFixed(5)}, '
                                          '${selectedPoint.longitude.toStringAsFixed(5)}',
                                          style: const TextStyle(fontSize: 11),
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
                              onPressed: selectedPoint == null
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
      ),
    );
  }
}
