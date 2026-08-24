import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class JourneyPlannerScreen extends StatefulWidget {
  const JourneyPlannerScreen({super.key});

  @override
  State<JourneyPlannerScreen> createState() => _JourneyPlannerScreenState();
}

class _JourneyPlannerScreenState extends State<JourneyPlannerScreen> {
  final TextEditingController _originController = TextEditingController(
    text: 'Current Location',
  );

  final TextEditingController _destinationController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  bool _departAt = true;
  bool _accessibleOnly = false;
  bool _fewerTransfers = false;
  bool _showRouteResults = false;

  double _maximumWalkingDistance = 800;

  String _routePreference = 'Recommended';

  final Set<String> _selectedModes = {'Bus', 'MRT'};

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _swapLocations() {
    final origin = _originController.text;
    final destination = _destinationController.text;

    setState(() {
      _originController.text = destination;
      _destinationController.text = origin;
    });
  }

  Future<void> _selectDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selectedDate == null || !mounted) return;

    setState(() {
      _selectedDate = selectedDate;
    });
  }

  Future<void> _selectTime() async {
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );

    if (selectedTime == null || !mounted) return;

    setState(() {
      _selectedTime = selectedTime;
    });
  }

  void _findRoutes() {
    if (_originController.text.trim().isEmpty ||
        _destinationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an origin and destination.'),
        ),
      );
      return;
    }

    if (_selectedModes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one transport mode.'),
        ),
      );
      return;
    }

    setState(() {
      _showRouteResults = true;
    });
  }

  String get _formattedDate {
    final day = _selectedDate.day.toString().padLeft(2, '0');
    final month = _selectedDate.month.toString().padLeft(2, '0');

    return '$day/$month/${_selectedDate.year}';
  }

  IconData _getModeIcon(String mode) {
    switch (mode) {
      case 'Bus':
        return Icons.directions_bus;
      case 'MRT':
        return Icons.subway;
      case 'LRT':
        return Icons.tram;
      case 'KTM':
        return Icons.train;
      case 'Monorail':
        return Icons.commute;
      default:
        return Icons.directions_transit;
    }
  }

  Color _getModeColour(String mode) {
    switch (mode) {
      case 'Bus':
        return const Color(0xFF2E7D32);
      case 'MRT':
        return const Color(0xFFD32F2F);
      case 'LRT':
        return const Color(0xFFF9A825);
      case 'KTM':
        return AppTheme.primaryBlue;
      case 'Monorail':
        return const Color(0xFF7B1FA2);
      default:
        return AppTheme.secondaryText;
    }
  }

  void _showJourneyDetails({
    required String title,
    required List<String> steps,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Step-by-step directions',
                  style: TextStyle(color: AppTheme.secondaryText),
                ),

                const SizedBox(height: 20),

                for (int index = 0; index < steps.length; index++)
                  _buildDirectionStep(
                    number: index + 1,
                    description: steps[index],
                    isLast: index == steps.length - 1,
                  ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(bottomSheetContext);
                      _showMessage('Journey started.');
                    },
                    child: const Text(
                      'Start Journey',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _buildLocationCard(),

        const SizedBox(height: 24),

        _buildSectionTitle(icon: Icons.schedule, title: 'Journey Time'),

        const SizedBox(height: 12),

        _buildJourneyTimeSection(),

        const SizedBox(height: 24),

        _buildSectionTitle(
          icon: Icons.directions_transit,
          title: 'Transport Modes',
        ),

        const SizedBox(height: 12),

        _buildTransportModes(),

        const SizedBox(height: 24),

        _buildSectionTitle(icon: Icons.tune, title: 'Route Preferences'),

        const SizedBox(height: 12),

        _buildRoutePreferences(),

        const SizedBox(height: 24),

        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _findRoutes,
            icon: const Icon(Icons.search),
            label: const Text(
              'Find Routes',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),

        if (_showRouteResults) ...[
          const SizedBox(height: 32),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Route Options',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _findRoutes,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),

          const SizedBox(height: 4),

          Text(
            '${_originController.text} → '
            '${_destinationController.text}',
            style: const TextStyle(color: AppTheme.secondaryText),
          ),

          const SizedBox(height: 16),

          _buildRouteOptionCard(
            recommended: true,
            title: 'Recommended Route',
            duration: '45 min',
            arrival: 'Arrive 10:45 AM',
            fare: 'RM 3.50',
            walking: '350 m',
            transfers: '1 transfer',
            modes: const ['Walk', 'Bus', 'KTM'],
            onViewDetails: () {
              _showJourneyDetails(
                title: 'Recommended Route',
                steps: const [
                  'Walk 200 m to the nearest bus stop.',
                  'Take Rapid Penang bus service.',
                  'Transfer to KTM Komuter.',
                  'Walk 150 m to your destination.',
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          _buildRouteOptionCard(
            title: 'Fastest Route',
            duration: '38 min',
            arrival: 'Arrive 10:38 AM',
            fare: 'RM 5.20',
            walking: '600 m',
            transfers: '2 transfers',
            modes: const ['Walk', 'Bus', 'MRT'],
            onViewDetails: () {
              _showJourneyDetails(
                title: 'Fastest Route',
                steps: const [
                  'Walk 300 m to the transport station.',
                  'Take the selected bus service.',
                  'Transfer to the MRT service.',
                  'Walk 300 m to your destination.',
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          _buildRouteOptionCard(
            title: 'Lowest Fare',
            duration: '55 min',
            arrival: 'Arrive 10:55 AM',
            fare: 'RM 2.00',
            walking: '800 m',
            transfers: 'No transfer',
            modes: const ['Walk', 'Bus'],
            onViewDetails: () {
              _showJourneyDetails(
                title: 'Lowest Fare Route',
                steps: const [
                  'Walk 400 m to the bus stop.',
                  'Take the direct bus service.',
                  'Walk 400 m to your destination.',
                ],
              );
            },
          ),

          const SizedBox(height: 12),

          const Text(
            'Route details and fares shown here are '
            'prototype examples. Actual values will be '
            'loaded from supported datasets.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTitle({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryBlue, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.my_location, color: AppTheme.primaryBlue),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _originController,
                  decoration: const InputDecoration(
                    labelText: 'Origin',
                    hintText: 'Enter starting location',
                  ),
                ),
              ),
              IconButton(
                onPressed: _swapLocations,
                tooltip: 'Swap locations',
                icon: const Icon(Icons.swap_vert, color: AppTheme.primaryBlue),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _destinationController,
                  decoration: const InputDecoration(
                    labelText: 'Destination',
                    hintText: 'Where do you want to go?',
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  _showMessage(
                    'Map selection will be added with '
                    'the Transit Map module.',
                  );
                },
                tooltip: 'Select on map',
                icon: const Icon(Icons.map_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJourneyTimeSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const SizedBox(
                  width: double.infinity,
                  child: Text('Depart At', textAlign: TextAlign.center),
                ),
                selected: _departAt,
                onSelected: (_) {
                  setState(() {
                    _departAt = true;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChoiceChip(
                label: const SizedBox(
                  width: double.infinity,
                  child: Text('Arrive By', textAlign: TextAlign.center),
                ),
                selected: !_departAt,
                onSelected: (_) {
                  setState(() {
                    _departAt = false;
                  });
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildSelectionBox(
                icon: Icons.calendar_today,
                label: _formattedDate,
                onTap: _selectDate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSelectionBox(
                icon: Icons.schedule,
                label: _selectedTime.format(context),
                onTap: _selectTime,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectionBox({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryBlue, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportModes() {
    const modes = ['Bus', 'MRT', 'LRT', 'KTM', 'Monorail'];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: modes.map((mode) {
        final selected = _selectedModes.contains(mode);
        final colour = _getModeColour(mode);

        return FilterChip(
          avatar: Icon(
            _getModeIcon(mode),
            size: 19,
            color: selected ? Colors.white : colour,
          ),
          label: Text(mode),
          selected: selected,
          showCheckmark: false,
          selectedColor: colour,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppTheme.mainText,
            fontWeight: FontWeight.w500,
          ),
          onSelected: (isSelected) {
            setState(() {
              if (isSelected) {
                _selectedModes.add(mode);
              } else {
                _selectedModes.remove(mode);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildRoutePreferences() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Route priority',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Recommended', 'Fastest', 'Lowest Fare', 'Least Walking']
                .map((preference) {
                  return ChoiceChip(
                    label: Text(preference),
                    selected: _routePreference == preference,
                    onSelected: (_) {
                      setState(() {
                        _routePreference = preference;
                      });
                    },
                  );
                })
                .toList(),
          ),

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Maximum walking distance',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                '${_maximumWalkingDistance.round()} m',
                style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          Slider(
            value: _maximumWalkingDistance,
            min: 200,
            max: 2000,
            divisions: 9,
            label: '${_maximumWalkingDistance.round()} m',
            onChanged: (value) {
              setState(() {
                _maximumWalkingDistance = value;
              });
            },
          ),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _accessibleOnly,
            secondary: const Icon(Icons.accessible, color: Color(0xFF00897B)),
            title: const Text('Accessible stations only'),
            subtitle: const Text('Avoid stations without required facilities'),
            onChanged: (value) {
              setState(() {
                _accessibleOnly = value;
              });
            },
          ),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _fewerTransfers,
            secondary: const Icon(Icons.multiple_stop),
            title: const Text('Fewer transfers'),
            subtitle: const Text('Prefer journeys with fewer interchanges'),
            onChanged: (value) {
              setState(() {
                _fewerTransfers = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRouteOptionCard({
    bool recommended = false,
    required String title,
    required String duration,
    required String arrival,
    required String fare,
    required String walking,
    required String transfers,
    required List<String> modes,
    required VoidCallback onViewDetails,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: recommended ? AppTheme.primaryBlue : AppTheme.border,
          width: recommended ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recommended) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'RECOMMENDED',
                style: TextStyle(
                  color: AppTheme.primaryBlue,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  _showMessage('$title saved.');
                },
                tooltip: 'Save journey',
                icon: const Icon(Icons.bookmark_border),
              ),
            ],
          ),

          Text(
            '$duration • $arrival',
            style: const TextStyle(color: AppTheme.secondaryText),
          ),

          const SizedBox(height: 16),

          _buildModeTimeline(modes),

          const SizedBox(height: 16),

          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _buildRouteInformation(icon: Icons.payments_outlined, text: fare),
              _buildRouteInformation(
                icon: Icons.directions_walk,
                text: walking,
              ),
              _buildRouteInformation(
                icon: Icons.multiple_stop,
                text: transfers,
              ),
              if (_accessibleOnly)
                _buildRouteInformation(
                  icon: Icons.accessible,
                  text: 'Accessible',
                  colour: const Color(0xFF00897B),
                ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onViewDetails,
                  child: const Text('View Details'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    _showMessage('$title selected.');
                  },
                  child: const Text('Select'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeTimeline(List<String> modes) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 8,
      children: [
        for (int index = 0; index < modes.length; index++) ...[
          _buildTimelineMode(modes[index]),
          if (index < modes.length - 1)
            const Icon(
              Icons.arrow_forward,
              size: 17,
              color: AppTheme.secondaryText,
            ),
        ],
      ],
    );
  }

  Widget _buildTimelineMode(String mode) {
    if (mode == 'Walk') {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_walk, size: 20, color: AppTheme.secondaryText),
          SizedBox(width: 4),
          Text('Walk'),
        ],
      );
    }

    final colour = _getModeColour(mode);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getModeIcon(mode), size: 19, color: colour),
          const SizedBox(width: 4),
          Text(
            mode,
            style: TextStyle(color: colour, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInformation({
    required IconData icon,
    required String text,
    Color colour = AppTheme.secondaryText,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: colour),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 13, color: colour)),
      ],
    );
  }

  Widget _buildDirectionStep({
    required int number,
    required String description,
    required bool isLast,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryBlue,
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: AppTheme.border)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 24),
              child: Text(description),
            ),
          ),
        ],
      ),
    );
  }
}
