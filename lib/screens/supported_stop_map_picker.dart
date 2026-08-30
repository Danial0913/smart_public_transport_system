import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/transit_models.dart';
import '../theme/app_theme.dart';

class SupportedStopMapPicker extends StatefulWidget {
  const SupportedStopMapPicker({
    super.key,
    required this.title,
    required this.stops,
    this.initialStop,
  });

  final String title;
  final List<TransitStop> stops;
  final TransitStop? initialStop;

  @override
  State<SupportedStopMapPicker> createState() =>
      _SupportedStopMapPickerState();
}

class _SupportedStopMapPickerState extends State<SupportedStopMapPicker> {
  TransitStop? _selectedStop;

  @override
  void initState() {
    super.initState();
    _selectedStop = widget.initialStop;
  }

  @override
  Widget build(BuildContext context) {
    final initialStop = widget.initialStop;
    final initialCentre = initialStop == null
        ? const LatLng(4.2, 102.0)
        : LatLng(initialStop.latitude, initialStop.longitude);

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
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
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
                      initialZoom: initialStop == null ? 6 : 12,
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
                        markers: widget.stops.map((stop) {
                          final selected = _selectedStop?.id == stop.id;
                          return Marker(
                            width: 46,
                            height: 46,
                            point: LatLng(stop.latitude, stop.longitude),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setState(() => _selectedStop = stop);
                              },
                              child: Tooltip(
                                message: stop.name,
                                child: Icon(
                                  Icons.location_on,
                                  size: selected ? 42 : 34,
                                  color: selected
                                      ? Colors.red
                                      : AppTheme.primaryBlue,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
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
                              child: Text(
                                _selectedStop?.name ??
                                    'Tap a marker to select a supported stop',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(84, 44),
                              ),
                              onPressed: _selectedStop == null
                                  ? null
                                  : () => Navigator.pop(
                                      context,
                                      _selectedStop,
                                    ),
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
