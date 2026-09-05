import 'package:flutter/material.dart';
import '../data/account_settings.dart';
import '../data/local_storage_service.dart';
import '../data/travel_settings.dart';
import '../data/journey_notification_service.dart';
import '../models/travel_preferences.dart';
import '../models/user_models.dart';
import '../theme/app_theme.dart';
import 'accessibility_screen.dart';
import 'login_screen.dart';
import 'account_form_screen.dart';
import 'privacy_security_screen.dart';
import 'saved_places_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.account,
    this.travelSettings,
    this.cancelReminders,
  });
  final AccountSettings? account;
  final TravelSettings? travelSettings;
  final Future<void> Function()? cancelReminders;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  TravelSettings get _travelSettings =>
      widget.travelSettings ?? LocalStorageService.instance;
  bool _travelLoading = true;
  bool _travelSaving = false;
  String? _travelError;
  bool _savedNotificationEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() {
      _travelLoading = true;
      _travelError = null;
    });
    try {
      final preferences = await _travelSettings.getTravelPreferences();
      if (!mounted) return;
      setState(() {
        _selectedTransport
          ..clear()
          ..addAll(preferences.transportModes);
        _maximumWalkingDistance = preferences.maximumWalkingMetres / 1000;
        _preferLowestFare = preferences.preferLowestFare;
        _preferFewerTransfers = preferences.preferFewerTransfers;
        _travelNotifications = preferences.travelNotifications;
        _savedNotificationEnabled = preferences.travelNotifications;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _travelError =
              'Could not load travel preferences. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _travelLoading = false);
    }
  }

  Future<void> _savePreferences() async {
    setState(() => _travelSaving = true);
    final preferences = TravelPreferences(
      transportModes: Set.of(_selectedTransport),
      maximumWalkingMetres: (_maximumWalkingDistance * 1000).round(),
      preferLowestFare: _preferLowestFare,
      preferFewerTransfers: _preferFewerTransfers,
      travelNotifications: _travelNotifications,
    );
    try {
      await _travelSettings.saveTravelPreferences(preferences);
      if (_savedNotificationEnabled && !preferences.travelNotifications) {
        try {
          await (widget.cancelReminders ??
              JourneyNotificationService.instance.cancelAllReminders)();
        } catch (_) {
          if (mounted) {
            _showMessage(
              'Preferences saved. Existing reminders could not be cancelled; try saving again.',
            );
          }
          return;
        }
      }
      _savedNotificationEnabled = preferences.travelNotifications;
      if (mounted) {
        _showMessage('Travel preferences saved for new journey plans.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is AccountSettingsException
              ? error.message
              : 'Could not save travel preferences. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _travelSaving = false);
    }
  }

  AccountSettings get _account =>
      widget.account ?? LocalStorageService.instance;

  Future<void> _editAccount({bool changePassword = false}) async {
    if (_account.currentUser.value == null) {
      _showMessage('Please log in again to manage your account.');
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AccountFormScreen(
          account: _account,
          changePassword: changePassword,
        ),
      ),
    );
    if (saved == true && mounted) {
      _showMessage(
        changePassword
            ? 'Password updated. Use your new password next time you log in.'
            : 'Profile updated.',
      );
    }
  }

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
          if (_travelLoading) const LinearProgressIndicator(),
          if (_travelError != null) ...[
            Text(_travelError!),
            TextButton(
              onPressed: _loadPreferences,
              child: const Text('Retry Travel Preferences'),
            ),
          ],
          AbsorbPointer(
            absorbing: _travelLoading || _travelSaving || _travelError != null,
            child: Column(
              children: [
                _buildTransportPreferences(),
                const SizedBox(height: 14),
                _buildWalkingPreference(),
                const SizedBox(height: 14),
                _buildRoutePreferences(),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _travelLoading || _travelSaving || _travelError != null
                ? null
                : _savePreferences,
            child: Text(_travelSaving ? 'Saving…' : 'Save Travel Preferences'),
          ),
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

  Widget _buildProfileHeader() => ValueListenableBuilder<AppUser?>(
    valueListenable: _account.currentUser,
    builder: (context, user, _) => _buildAccountHeader(user),
  );

  Widget _buildAccountHeader(AppUser? user) {
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
                      color: Colors.white.withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.fullName ?? 'Please log in',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user?.phone ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
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
              onPressed: user == null ? null : () => _editAccount(),
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
                selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.13),
                checkmarkColor: AppTheme.primaryBlue,
                side: BorderSide(
                  color: isSelected ? AppTheme.primaryBlue : AppTheme.border,
                ),
                onSelected: (selected) {
                  if (!selected && _selectedTransport.length == 1) {
                    _showMessage('Keep at least one transport mode selected.');
                    return;
                  }
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
            activeThumbColor: AppTheme.primaryBlue,
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
            activeThumbColor: AppTheme.primaryBlue,
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
            activeThumbColor: AppTheme.primaryBlue,
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
              'Departure reminders for newly saved journeys. Turning this off also cancels existing reminders on this device.',
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

  Widget _buildSavedPlaces() => SavedPlacesCard(settings: _travelSettings);

  Widget _buildAccessibilityCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AccessibilityScreen()),
        );
      },
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF00897B).withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF00897B).withValues(alpha: 0.35),
          ),
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
            onTap: () => _editAccount(changePassword: true),
          ),
          const Divider(height: 1),
          _buildSettingTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy and Security',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PrivacySecurityScreen(account: _account),
                ),
              );
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
                _account.logout();
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
