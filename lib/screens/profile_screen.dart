import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Set<String> _selectedTransport = {'Bus', 'Train'};

  double _maximumWalkingDistance = 1.5;
  bool _preferLowestFare = true;
  bool _preferFewerTransfers = false;
  bool _travelNotifications = true;

  final List<TransportPreference> _transportOptions = const [
    TransportPreference(name: 'Bus', icon: Icons.directions_bus),
    TransportPreference(name: 'Train', icon: Icons.train),
    TransportPreference(name: 'Ferry', icon: Icons.directions_boat),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProfileHeader(),
          const SizedBox(height: 20),
          _buildSectionTitle(
            title: 'Travel Preferences',
            subtitle: 'Personalise your journey recommendations',
          ),
          const SizedBox(height: 12),
          _buildTransportPreferences(),
          const SizedBox(height: 14),
          _buildWalkingPreference(),
          const SizedBox(height: 14),
          _buildRoutePreferences(),
          const SizedBox(height: 22),
          _buildSectionTitle(
            title: 'Saved Places',
            subtitle: 'Quickly plan routes to frequent destinations',
          ),
          const SizedBox(height: 12),
          _buildSavedPlaces(),
          const SizedBox(height: 22),
          _buildAccessibilityCard(),
          const SizedBox(height: 22),
          _buildAccountSettings(),
          const SizedBox(height: 20),
          _buildLogoutButton(),
          const SizedBox(height: 15),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryBlue, AppTheme.darkBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 27,
                      height: 27,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primaryBlue,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        size: 15,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 15),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UserName',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'User@email.com',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '+60 12-345 6789',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _showMessage('Edit profile selected');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white),
              ),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit Profile'),
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

  Widget _buildTransportPreferences() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.commute, color: AppTheme.primaryBlue),
              SizedBox(width: 9),
              Text(
                'Preferred Transport Modes',
                style: TextStyle(
                  color: AppTheme.mainText,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: _transportOptions.map((transport) {
              final bool isSelected = _selectedTransport.contains(
                transport.name,
              );

              return FilterChip(
                selected: isSelected,
                avatar: Icon(
                  transport.icon,
                  size: 18,
                  color: isSelected
                      ? AppTheme.primaryBlue
                      : AppTheme.secondaryText,
                ),
                label: Text(transport.name),
                selectedColor: AppTheme.primaryBlue.withOpacity(0.13),
                checkmarkColor: AppTheme.primaryBlue,
                side: BorderSide(
                  color: isSelected ? AppTheme.primaryBlue : AppTheme.border,
                ),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedTransport.add(transport.name);
                    } else {
                      _selectedTransport.remove(transport.name);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWalkingPreference() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_walk, color: Color(0xFF00897B)),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Maximum Walking Distance',
                  style: TextStyle(
                    color: AppTheme.mainText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${_maximumWalkingDistance.toStringAsFixed(1)} km',
                style: const TextStyle(
                  color: Color(0xFF00897B),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: _maximumWalkingDistance,
            min: 0.5,
            max: 5.0,
            divisions: 9,
            activeColor: const Color(0xFF00897B),
            label: '${_maximumWalkingDistance.toStringAsFixed(1)} km',
            onChanged: (value) {
              setState(() {
                _maximumWalkingDistance = value;
              });
            },
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0.5 km',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 11),
              ),
              Text(
                '5.0 km',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoutePreferences() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
          children: [
          SwitchListTile(
            value: _preferLowestFare,
            activeColor: AppTheme.primaryBlue,
            secondary: const Icon(
              Icons.savings_outlined,
              color: Color(0xFFF57C00),
            ),
            title: const Text(
              'Prefer Lowest Fare',
              style: TextStyle(
                color: AppTheme.mainText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Prioritise routes with lower transport costs',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (value) {
              setState(() {
                _preferLowestFare = value;
              });
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _preferFewerTransfers,
            activeColor: AppTheme.primaryBlue,
            secondary: const Icon(
              Icons.compare_arrows,
              color: Color(0xFF7B1FA2),
            ),
            title: const Text(
              'Prefer Fewer Transfers',
              style: TextStyle(
                color: AppTheme.mainText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Reduce the number of transport changes',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (value) {
              setState(() {
                _preferFewerTransfers = value;
              });
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _travelNotifications,
            activeColor: AppTheme.primaryBlue,
            secondary: const Icon(
              Icons.notifications_active_outlined,
              color: AppTheme.primaryBlue,
            ),
            title: const Text(
              'Travel Notifications',
              style: TextStyle(
                color: AppTheme.mainText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Receive service delay and journey reminders',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (value) {
              setState(() {
                _travelNotifications = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSavedPlaces() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
          children: [
          _buildSavedPlaceTile(
            icon: Icons.home_outlined,
            title: 'Home',
            address: 'George Town, Penang',
            colour: AppTheme.primaryBlue,
          ),
          const Divider(height: 1),
          _buildSavedPlaceTile(
            icon: Icons.school_outlined,
            title: 'University',
            address: 'TAR UMT Penang Branch',
            colour: const Color(0xFF7B1FA2),
          ),
          const Divider(height: 1),
          ListTile(
            onTap: () {
              _showMessage('Add a new saved place');
            },
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add, color: AppTheme.primaryBlue),
            ),
            title: const Text(
              'Add Saved Place',
              style: TextStyle(
                color: AppTheme.primaryBlue,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedPlaceTile({
    required IconData icon,
    required String title,
    required String address,
    required Color colour,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colour.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: colour),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.mainText,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        address,
        style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12),
      ),
      trailing: IconButton(
        onPressed: () {
          _showMessage('Edit $title location');
        },
        icon: const Icon(Icons.edit_outlined, size: 19),
      ),
    );
  }

  Widget _buildAccessibilityCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        _showMessage(
          'The Accessibility Assistance page will be connected next',
        );
      },
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF00897B).withOpacity(0.09),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF00897B).withOpacity(0.35)),
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: Color(0xFF00897B),
              child: Icon(Icons.accessible, color: Colors.white, size: 28),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Accessibility Assistance',
                    style: TextStyle(
                      color: Color(0xFF00695C),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Set mobility needs and check accessible facilities.',
                    style: TextStyle(
                      color: AppTheme.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Color(0xFF00897B), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSettings() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
          children: [
          _buildSettingTile(
            icon: Icons.lock_outline,
            title: 'Change Password',
            onTap: () {
              _showMessage('Change password selected');
            },
          ),
          const Divider(height: 1),
          _buildSettingTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy and Security',
            onTap: () {
              _showMessage('Privacy settings selected');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? value,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppTheme.primaryBlue),
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.mainText,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(
              value,
              style: const TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 12,
              ),
            ),
          const SizedBox(width: 6),
          const Icon(
            Icons.arrow_forward_ios,
            size: 15,
            color: AppTheme.secondaryText,
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return OutlinedButton.icon(
      onPressed: _confirmLogout,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFD32F2F),
        side: const BorderSide(color: Color(0xFFD32F2F)),
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      icon: const Icon(Icons.logout),
      label: const Text('Log Out'),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Log Out'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
              ),
              child: const Text('Log Out'),
            ),
          ],
        );
      },
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

class TransportPreference {
  final String name;
  final IconData icon;

  const TransportPreference({required this.name, required this.icon});
}
