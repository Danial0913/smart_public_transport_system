import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AccessibilityScreen extends StatefulWidget {
  const AccessibilityScreen({super.key});

  @override
  State<AccessibilityScreen> createState() => _AccessibilityScreenState();
}

class _AccessibilityScreenState extends State<AccessibilityScreen> {
  static const Color accessibilityTeal = Color(0xFF00897B);

  final Set<String> _selectedNeeds = {'Wheelchair Access', 'Step-free Route'};

  bool _accessibleRoutesOnly = true;
  bool _workingLiftsOnly = true;
  bool _audioGuidance = false;
  bool _visualAlerts = true;

  final List<AccessibilityNeed> _accessibilityNeeds = const [
    AccessibilityNeed(name: 'Wheelchair Access', icon: Icons.accessible),
    AccessibilityNeed(name: 'Step-free Route', icon: Icons.escalator_warning),
    AccessibilityNeed(
      name: 'Audio Guidance',
      icon: Icons.record_voice_over_outlined,
    ),
    AccessibilityNeed(name: 'Visual Alerts', icon: Icons.visibility_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Accessibility Assistance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildIntroductionCard(),
          const SizedBox(height: 22),
          _buildSectionTitle(
            title: 'My Accessibility Needs',
            subtitle: 'Select the assistance required for your journeys',
          ),
          const SizedBox(height: 12),
          _buildAccessibilityNeeds(),
          const SizedBox(height: 22),
          _buildSectionTitle(
            title: 'Route Assistance Settings',
            subtitle: 'Control how accessible journeys are recommended',
          ),
          const SizedBox(height: 12),
          _buildAssistanceSettings(),
          const SizedBox(height: 22),
          _buildFacilityHeader(),
          const SizedBox(height: 12),
          _buildFacilityCard(
            stationName: 'KOMTAR Bus Terminal',
            distance: '0.4 km away',
            lastUpdated: 'Updated 5 minutes ago',
            facilities: const [
              FacilityInformation(
                name: 'Wheelchair Ramp',
                icon: Icons.accessible_forward,
                status: 'Available',
                available: true,
              ),
              FacilityInformation(
                name: 'Accessible Toilet',
                icon: Icons.wc,
                status: 'Available',
                available: true,
              ),
              FacilityInformation(
                name: 'Lift',
                icon: Icons.elevator_outlined,
                status: 'Available',
                available: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFacilityCard(
            stationName: 'Butterworth Railway Station',
            distance: '4.8 km away',
            lastUpdated: 'Updated 20 minutes ago',
            facilities: const [
              FacilityInformation(
                name: 'Wheelchair Ramp',
                icon: Icons.accessible_forward,
                status: 'Available',
                available: true,
              ),
              FacilityInformation(
                name: 'Accessible Toilet',
                icon: Icons.wc,
                status: 'Available',
                available: true,
              ),
              FacilityInformation(
                name: 'Lift',
                icon: Icons.elevator_outlined,
                status: 'Under maintenance',
                available: false,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _buildAssistanceHelp(),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildIntroductionCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00897B), Color(0xFF00695C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white24,
            child: Icon(Icons.accessibility_new, color: Colors.white, size: 34),
          ),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Travel with Confidence',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Find accessible routes and check facility availability before travelling.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.mainText,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(color: AppTheme.secondaryText, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildAccessibilityNeeds() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Wrap(
        spacing: 9,
        runSpacing: 9,
        children: _accessibilityNeeds.map((need) {
          final bool isSelected = _selectedNeeds.contains(need.name);

          return FilterChip(
            selected: isSelected,
            avatar: Icon(
              need.icon,
              size: 18,
              color: isSelected ? accessibilityTeal : AppTheme.secondaryText,
            ),
            label: Text(need.name),
            selectedColor: accessibilityTeal.withOpacity(0.13),
            checkmarkColor: accessibilityTeal,
            side: BorderSide(
              color: isSelected ? accessibilityTeal : AppTheme.border,
            ),
            labelStyle: TextStyle(
              color: isSelected ? accessibilityTeal : AppTheme.mainText,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _selectedNeeds.add(need.name);
                } else {
                  _selectedNeeds.remove(need.name);
                }
              });
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAssistanceSettings() {
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: [
          SwitchListTile(
            value: _accessibleRoutesOnly,
            activeColor: accessibilityTeal,
            secondary: const Icon(
              Icons.route_outlined,
              color: accessibilityTeal,
            ),
            title: const Text(
              'Accessible Routes Only',
              style: TextStyle(
                color: AppTheme.mainText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Only recommend step-free transport routes',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (value) {
              setState(() {
                _accessibleRoutesOnly = value;
              });
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _workingLiftsOnly,
            activeColor: accessibilityTeal,
            secondary: const Icon(
              Icons.elevator_outlined,
              color: accessibilityTeal,
            ),
            title: const Text(
              'Working Lifts Required',
              style: TextStyle(
                color: AppTheme.mainText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Avoid stations with unavailable lifts',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (value) {
              setState(() {
                _workingLiftsOnly = value;
              });
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _audioGuidance,
            activeColor: accessibilityTeal,
            secondary: const Icon(
              Icons.volume_up_outlined,
              color: accessibilityTeal,
            ),
            title: const Text(
              'Audio Guidance',
              style: TextStyle(
                color: AppTheme.mainText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Read journey instructions aloud',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (value) {
              setState(() {
                _audioGuidance = value;
              });
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _visualAlerts,
            activeColor: accessibilityTeal,
            secondary: const Icon(
              Icons.notifications_active_outlined,
              color: accessibilityTeal,
            ),
            title: const Text(
              'Visual Alerts',
              style: TextStyle(
                color: AppTheme.mainText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Show visible service and arrival alerts',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (value) {
              setState(() {
                _visualAlerts = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFacilityHeader() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nearby Accessible Facilities',
                style: TextStyle(
                  color: AppTheme.mainText,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Facility status at nearby stations',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh facility status',
          onPressed: () {
            _showMessage('Facility information refreshed');
          },
          icon: const Icon(Icons.refresh, color: accessibilityTeal),
        ),
      ],
    );
  }

  Widget _buildFacilityCard({
    required String stationName,
    required String distance,
    required String lastUpdated,
    required List<FacilityInformation> facilities,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: accessibilityTeal.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.location_city,
                  color: accessibilityTeal,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stationName,
                      style: const TextStyle(
                        color: AppTheme.mainText,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      distance,
                      style: const TextStyle(
                        color: AppTheme.secondaryText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'View on map',
                onPressed: () {
                  _showMessage('Showing $stationName on the map');
                },
                icon: const Icon(
                  Icons.map_outlined,
                  color: AppTheme.primaryBlue,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          ...facilities.map((facility) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: _buildFacilityStatus(facility),
            );
          }),
          Row(
            children: [
              const Icon(Icons.update, size: 13, color: AppTheme.secondaryText),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  lastUpdated,
                  style: const TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 10,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  _showMessage('Report facility information for $stationName');
                },
                child: const Text(
                  'Report issue',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFacilityStatus(FacilityInformation facility) {
    final Color statusColour = facility.available
        ? const Color(0xFF2E7D32)
        : const Color(0xFFD32F2F);

    return Row(
      children: [
        Icon(facility.icon, color: accessibilityTeal, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            facility.name,
            style: const TextStyle(color: AppTheme.mainText, fontSize: 13),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: statusColour.withOpacity(0.10),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                facility.available ? Icons.check_circle : Icons.warning_rounded,
                color: statusColour,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                facility.status,
                style: TextStyle(
                  color: statusColour,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAssistanceHelp() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.support_agent, color: AppTheme.primaryBlue, size: 28),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need Travel Assistance?',
                      style: TextStyle(
                        color: AppTheme.mainText,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Request assistance from station personnel.',
                      style: TextStyle(
                        color: AppTheme.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                _showMessage('Assistance request submitted');
              },
              icon: const Icon(Icons.waving_hand_outlined),
              label: const Text('Request Assistance'),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }
}

class AccessibilityNeed {
  final String name;
  final IconData icon;

  const AccessibilityNeed({required this.name, required this.icon});
}

class FacilityInformation {
  final String name;
  final IconData icon;
  final String status;
  final bool available;

  const FacilityInformation({
    required this.name,
    required this.icon,
    required this.status,
    required this.available,
  });
}
