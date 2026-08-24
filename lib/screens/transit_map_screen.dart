import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TransitMapScreen extends StatefulWidget {
  const TransitMapScreen({super.key});

  @override
  State<TransitMapScreen> createState() => _TransitMapScreenState();
}

class _TransitMapScreenState extends State<TransitMapScreen> {
  String _selectedMode = 'All';
  TransitVehicle? _selectedVehicle;

  final List<String> _transportModes = ['All', 'Bus', 'Train', 'Ferry'];

  final List<TransitVehicle> _vehicles = const [
    TransitVehicle(
      name: 'Rapid Penang 101',
      type: 'Bus',
      location: 'Near KOMTAR Bus Terminal',
      arrivalTime: '3 min',
      status: 'On time',
      alignment: Alignment(-0.65, -0.45),
      icon: Icons.directions_bus,
      colour: AppTheme.primaryBlue,
    ),
    TransitVehicle(
      name: 'Rapid Penang 204',
      type: 'Bus',
      location: 'Near Jalan Macalister',
      arrivalTime: '6 min',
      status: 'Slight delay',
      alignment: Alignment(0.55, -0.10),
      icon: Icons.directions_bus,
      colour: Color(0xFFF57C00),
    ),
    TransitVehicle(
      name: 'KTM Komuter 2944',
      type: 'Train',
      location: 'Butterworth Railway Station',
      arrivalTime: '8 min',
      status: 'On time',
      alignment: Alignment(-0.20, 0.40),
      icon: Icons.train,
      colour: Color(0xFF7B1FA2),
    ),
    TransitVehicle(
      name: 'Penang Ferry',
      type: 'Ferry',
      location: 'Raja Tun Uda Ferry Terminal',
      arrivalTime: '5 min',
      status: 'Boarding soon',
      alignment: Alignment(0.60, 0.52),
      icon: Icons.directions_boat,
      colour: Color(0xFF00897B),
    ),
  ];

  List<TransitVehicle> get _filteredVehicles {
    if (_selectedMode == 'All') {
      return _vehicles;
    }

    return _vehicles.where((vehicle) => vehicle.type == _selectedMode).toList();
  }

  void _selectMode(String mode) {
    setState(() {
      _selectedMode = mode;
      _selectedVehicle = null;
    });
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
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search station, stop or route',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            onPressed: () {},
            icon: const Icon(Icons.mic_none),
          ),
        ),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Searching for "$value"')));
          }
        },
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
            final bool isSelected = _selectedMode == mode;

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

  Widget _buildMapSection() {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: const Color(0xFFEAF2F8),
            child: CustomPaint(painter: TransitMapPainter()),
          ),
        ),

        // Live status label
        Positioned(
          left: 16,
          top: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 8),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 10, color: Color(0xFF2E7D32)),
                SizedBox(width: 7),
                Text(
                  'Live tracking',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.mainText,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Map control buttons
        Positioned(
          right: 16,
          top: 16,
          child: Column(
            children: [
              _buildMapControlButton(
                icon: Icons.layers_outlined,
                onPressed: () {
                  _showMessage('Map layers selected');
                },
              ),
              const SizedBox(height: 10),
              _buildMapControlButton(
                icon: Icons.my_location,
                onPressed: () {
                  _showMessage('Showing your current location');
                },
              ),
              const SizedBox(height: 10),
              _buildMapControlButton(
                icon: Icons.refresh,
                onPressed: () {
                  _showMessage('Live vehicle locations refreshed');
                },
              ),
            ],
          ),
        ),

        // Transport vehicle markers
        ..._filteredVehicles.map(_buildVehicleMarker),

        // User's current location
        const Align(
          alignment: Alignment(0.25, 0.15),
          child: CurrentLocationMarker(),
        ),

        // Instruction shown before selecting a vehicle
        if (_selectedVehicle == null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.touch_app_outlined, color: AppTheme.primaryBlue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Select a vehicle marker to view its live information.',
                      style: TextStyle(color: AppTheme.mainText, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Selected vehicle information
        if (_selectedVehicle != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _buildVehicleInformationCard(_selectedVehicle!),
          ),
      ],
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: AppTheme.primaryBlue),
      ),
    );
  }

  Widget _buildVehicleMarker(TransitVehicle vehicle) {
    final bool isSelected = _selectedVehicle == vehicle;

    return Align(
      alignment: vehicle.alignment,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedVehicle = vehicle;
          });
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSelected ? 54 : 46,
              height: isSelected ? 54 : 46,
              decoration: BoxDecoration(
                color: vehicle.colour,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                vehicle.icon,
                color: Colors.white,
                size: isSelected ? 28 : 24,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                vehicle.arrivalTime,
                style: TextStyle(
                  color: vehicle.colour,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleInformationCard(TransitVehicle vehicle) {
    final bool isDelayed = vehicle.status == 'Slight delay';

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: vehicle.colour.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(vehicle.icon, color: vehicle.colour),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.name,
                        style: const TextStyle(
                          color: AppTheme.mainText,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        vehicle.location,
                        style: const TextStyle(
                          color: AppTheme.secondaryText,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedVehicle = null;
                    });
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildInformationItem(
                    title: 'Arrival',
                    value: vehicle.arrivalTime,
                    icon: Icons.schedule,
                    colour: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildInformationItem(
                    title: 'Status',
                    value: vehicle.status,
                    icon: isDelayed
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    colour: isDelayed
                        ? const Color(0xFFF57C00)
                        : const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  _showMessage('Tracking ${vehicle.name}');
                },
                icon: const Icon(Icons.near_me_outlined),
                label: const Text('Track This Vehicle'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInformationItem({
    required String title,
    required String value,
    required IconData icon,
    required Color colour,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colour.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: colour, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colour,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }
}

class CurrentLocationMarker extends StatelessWidget {
  const CurrentLocationMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 25,
      height: 25,
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.25),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}

class TransitVehicle {
  final String name;
  final String type;
  final String location;
  final String arrivalTime;
  final String status;
  final Alignment alignment;
  final IconData icon;
  final Color colour;

  const TransitVehicle({
    required this.name,
    required this.type,
    required this.location,
    required this.arrivalTime,
    required this.status,
    required this.alignment,
    required this.icon,
    required this.colour,
  });
}

class TransitMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint minorRoadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    final Paint majorRoadPaint = Paint()
      ..color = const Color(0xFFCAD6E2)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    final Paint waterPaint = Paint()
      ..color = const Color(0xFFB9DDF5)
      ..strokeWidth = 55
      ..strokeCap = StrokeCap.round;

    // Water area
    final Path waterPath = Path()
      ..moveTo(size.width * 0.05, size.height)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.55,
        size.width,
        size.height * 0.70,
      );

    canvas.drawPath(waterPath, waterPaint);

    // Major roads
    canvas.drawLine(
      Offset(size.width * 0.10, size.height * 0.20),
      Offset(size.width * 0.90, size.height * 0.65),
      majorRoadPaint,
    );

    canvas.drawLine(
      Offset(size.width * 0.25, size.height * 0.05),
      Offset(size.width * 0.45, size.height * 0.90),
      majorRoadPaint,
    );

    // Minor roads
    canvas.drawLine(
      Offset(0, size.height * 0.35),
      Offset(size.width, size.height * 0.25),
      minorRoadPaint,
    );

    canvas.drawLine(
      Offset(0, size.height * 0.58),
      Offset(size.width, size.height * 0.48),
      minorRoadPaint,
    );

    canvas.drawLine(
      Offset(size.width * 0.65, 0),
      Offset(size.width * 0.70, size.height),
      minorRoadPaint,
    );

    canvas.drawLine(
      Offset(size.width * 0.08, 0),
      Offset(size.width * 0.18, size.height),
      minorRoadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
