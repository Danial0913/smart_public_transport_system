import 'package:flutter/material.dart';
import 'package:smart_tublic_transport_system/screens/profile_screen.dart';

import '../theme/app_theme.dart';
import 'journey_planner_screen.dart';
import 'transit_map_screen.dart';
import 'travel_history_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final TextEditingController _originController = TextEditingController(
    text: 'Current Location',
  );

  final TextEditingController _destinationController = TextEditingController();

  static const List<String> _pageTitles = [
    'Home',
    'Plan Journey',
    'Transit Map',
    'Travel History',
    'Profile & Settings',
  ];

  static const List<IconData> _pageIcons = [
    Icons.home,
    Icons.route,
    Icons.map,
    Icons.history,
    Icons.person,
  ];

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _changePage(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _swapLocations() {
    final origin = _originController.text;
    final destination = _destinationController.text;

    setState(() {
      _originController.text = destination;
      _destinationController.text = origin;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectedIndex == 0
          ? _buildHomeAppBar()
          : AppBar(
              automaticallyImplyLeading: false,
              title: Text(
                _pageTitles[_selectedIndex],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomePage(),
          const JourneyPlannerScreen(),
          TransitMapScreen(),
          TravelHistoryScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _changePage,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildHomeAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 72,
      titleSpacing: 16,
      title: const Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFFE3F2FD),
            child: Text(
              'UN',
              style: TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good Morning,',
                style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
              ),
              Text(
                'UserName',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkBlue,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        Stack(
          children: [
            IconButton(
              onPressed: () {
                _showMessage('You have no new notifications.');
              },
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_outlined),
            ),
            Positioned(
              top: 12,
              right: 11,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildHomePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location
          InkWell(
            onTap: () {
              _showMessage('Location selection will be added later.');
            },
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on,
                    color: AppTheme.primaryBlue,
                    size: 21,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Penang',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          _buildJourneySearchCard(),

          const SizedBox(height: 24),

          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),

          const SizedBox(height: 12),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.05,
            children: [
              _buildQuickAction(
                icon: Icons.route,
                label: 'Plan Journey',
                colour: AppTheme.primaryBlue,
                onTap: () => _changePage(1),
              ),
              _buildQuickAction(
                icon: Icons.map_outlined,
                label: 'Live Map',
                colour: const Color(0xFF00897B),
                onTap: () => _changePage(2),
              ),
              _buildQuickAction(
                icon: Icons.accessible,
                label: 'Accessibility',
                colour: const Color(0xFF00897B),
                onTap: () {
                  _showMessage('Accessibility module will be added later.');
                },
              ),
              _buildQuickAction(
                icon: Icons.add_circle_outline,
                label: 'Add Journey',
                colour: const Color(0xFFF57C00),
                onTap: () => _changePage(3),
              ),
            ],
          ),

          const SizedBox(height: 24),

          _buildSectionHeader(
            title: 'Upcoming Journey',
            actionText: 'See All',
            onAction: () {
              _showMessage('Saved journeys will be added later.');
            },
          ),

          const SizedBox(height: 12),

          _buildUpcomingJourneyCard(),

          const SizedBox(height: 24),

          _buildSectionHeader(
            title: 'Favourites',
            actionText: 'Manage',
            onAction: () {
              _showMessage('Favourite management will be added later.');
            },
          ),

          const SizedBox(height: 12),

          _buildFavourites(),

          const SizedBox(height: 24),

          _buildSectionHeader(
            title: 'Nearby Transport',
            actionText: 'View Map',
            onAction: () => _changePage(2),
          ),

          const SizedBox(height: 12),

          _buildNearbyTransportCard(
            icon: Icons.directions_bus,
            iconColour: const Color(0xFF2E7D32),
            title: 'Rapid Penang 101',
            description: 'Towards Jetty • 200 m away',
            time: '3 min',
            status: 'Example live status',
            statusColour: const Color(0xFFF57C00),
          ),

          const SizedBox(height: 12),

          _buildNearbyTransportCard(
            icon: Icons.train,
            iconColour: AppTheme.primaryBlue,
            title: 'KTM Komuter',
            description: 'Butterworth Station • 1.2 km',
            time: '12 min',
            status: 'Static schedule',
            statusColour: const Color(0xFF2E7D32),
          ),
        ],
      ),
    );
  }

  Widget _buildJourneySearchCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
                    hintText: 'Origin',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
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

          const Divider(height: 1),

          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _destinationController,
                  decoration: const InputDecoration(
                    hintText: 'Where do you want to go?',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () {
                _changePage(1);
              },
              icon: const Icon(Icons.route),
              label: const Text(
                'Plan Journey',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color colour,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: colour),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String actionText,
    required VoidCallback onAction,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        TextButton(onPressed: onAction, child: Text(actionText)),
      ],
    );
  }

  Widget _buildUpcomingJourneyCard() {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.directions_bus,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Campus to Komtar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Today • 10:30 AM',
                      style: TextStyle(
                        color: AppTheme.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.bookmark, color: AppTheme.primaryBlue),
            ],
          ),

          const SizedBox(height: 16),

          const Row(
            children: [
              Icon(Icons.schedule, size: 18, color: AppTheme.secondaryText),
              SizedBox(width: 6),
              Text('45 minutes'),
              SizedBox(width: 16),
              Icon(
                Icons.directions_walk,
                size: 18,
                color: AppTheme.secondaryText,
              ),
              SizedBox(width: 6),
              Text('350 m'),
            ],
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: null, child: Text('View Journey')),
          ),
        ],
      ),
    );
  }

  Widget _buildFavourites() {
    final favourites = [
      (icon: Icons.home, title: 'Home', colour: AppTheme.primaryBlue),
      (icon: Icons.school, title: 'Campus', colour: const Color(0xFF00897B)),
      (icon: Icons.work, title: 'Work', colour: const Color(0xFFF57C00)),
      (icon: Icons.add, title: 'Add New', colour: AppTheme.secondaryText),
    ];

    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: favourites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final favourite = favourites[index];

          return InkWell(
            onTap: () {
              _showMessage('${favourite.title} selected.');
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 112,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: favourite.colour.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(favourite.icon, color: favourite.colour),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    favourite.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNearbyTransportCard({
    required IconData icon,
    required Color iconColour,
    required String title,
    required String description,
    required String time,
    required String status,
    required Color statusColour,
  }) {
    return InkWell(
      onTap: () {
        _showMessage('$title selected.');
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColour.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColour),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: iconColour,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(fontSize: 10, color: statusColour),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderPage({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE3F2FD),
              ),
              child: Icon(icon, size: 44, color: AppTheme.primaryBlue),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}
