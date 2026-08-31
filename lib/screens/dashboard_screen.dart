import 'package:flutter/material.dart';

import '../data/geocoding_service.dart';
import '../data/local_storage_service.dart';
import '../data/location_service.dart';
import '../data/ridership_api_service.dart';
import '../data/transit_repository.dart';
import '../models/ridership_models.dart';
import '../models/transit_models.dart';
import '../theme/app_theme.dart';
import 'journey_planner_screen.dart';
import 'profile_screen.dart';
import 'supported_stop_map_picker.dart';
import 'transit_map_screen.dart';
import 'travel_history_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final LocalStorageService _storage = LocalStorageService.instance;
  final TransitRepository _repository = TransitRepository.instance;
  final LocationService _locationService = LocationService();
  final GeocodingService _geocodingService = GeocodingService();
  final RidershipApiService _ridershipApiService = RidershipApiService();

  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  JourneyLocation? _originLocation;
  JourneyLocation? _destinationLocation;

  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _gettingLocation = false;
  Key _plannerKey = UniqueKey();
  String? _selectedCategoryId;
  JourneyOption? _activeJourney;
  Key _mapKey = UniqueKey();

  List<FavouriteCategory> _categories = [];
  List<FavouriteItem> _favourites = [];
  List<RecentSearch> _recentSearches = [];
  List<SavedJourney> _savedJourneys = [];
  List<ServiceUsage> _frequentServices = [];

  late Future<List<PublicTransportRidership>> _publicTransportRidership;
  late Future<List<KtmbRidership>> _ktmbRidership;

  static const List<String> _pageTitles = [
    'Home',
    'Plan Journey',
    'Transit Map',
    'Travel History',
    'Profile & Settings',
  ];

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _fetchDashboardData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _publicTransportRidership =
            _ridershipApiService.fetchPublicTransportRidership();
        _ktmbRidership = _ridershipApiService.fetchKtmbRidership();
      });
    }

    try {
      await _repository.load();
      await _storage.initialise();

      final categories = await _storage.getFavouriteCategories();
      final favourites = await _storage.getFavourites();
      final recentSearches = await _storage.getRecentSearches();
      final savedJourneys = await _storage.getSavedJourneys();
      final frequentServices = await _storage.getFrequentServices();

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _favourites = favourites;
        _recentSearches = recentSearches;
        _savedJourneys = savedJourneys;
        _frequentServices = frequentServices;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showMessage('Failed to load dashboard data: $error');
    }
  }

  void _changePage(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 0) {
      _fetchDashboardData();
    }
  }

  void _openPlanner({
    String? origin,
    String? destination,
    JourneyLocation? originLocation,
    JourneyLocation? destinationLocation,
  }) {
    setState(() {
      if (originLocation != null) {
        _originLocation = originLocation;
        _originController.text = originLocation.name;
      } else if (origin != null && origin.isNotEmpty) {
        final stop = _repository.findStop(origin);
        _originLocation =
            stop == null ? null : JourneyLocation.fromStop(stop);
        _originController.text = origin;
      }
      if (destinationLocation != null) {
        _destinationLocation = destinationLocation;
        _destinationController.text = destinationLocation.name;
      } else if (destination != null) {
        final stop = _repository.findStop(destination);
        _destinationLocation =
            stop == null ? null : JourneyLocation.fromStop(stop);
        _destinationController.text = destination;
      }
      _plannerKey = UniqueKey();
      _selectedIndex = 1;
    });
  }

  void _swapLocations() {
    final origin = _originController.text;
    final originLocation = _originLocation;
    setState(() {
      _originController.text = _destinationController.text;
      _destinationController.text = origin;
      _originLocation = _destinationLocation;
      _destinationLocation = originLocation;
    });
  }

  Future<void> _selectLocationFromMap({
    required TextEditingController controller,
    required String title,
    required bool isOrigin,
  }) async {
    final selectedLocation = await Navigator.push<JourneyLocation>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SupportedStopMapPicker(
          title: title,
          stops: _repository.stops,
          initialLocation: isOrigin ? _originLocation : _destinationLocation,
        ),
      ),
    );

    if (selectedLocation == null || !mounted) return;
    setState(() {
      controller.text = selectedLocation.name;
      if (isOrigin) {
        _originLocation = selectedLocation;
      } else {
        _destinationLocation = selectedLocation;
      }
    });
  }

  Future<void> _useGpsForOrigin() async {
    if (_gettingLocation) return;
    setState(() => _gettingLocation = true);

    try {
      final currentLocation = await _locationService.getCurrentLocation();
      final latitude = currentLocation?.latitude;
      final longitude = currentLocation?.longitude;

      if (latitude == null || longitude == null) {
        if (mounted) {
          _showMessage(
            _locationService.lastErrorMessage ??
                'Location permission or GPS service is not available.',
          );
        }
        return;
      }

      if (!LocationService.isInsideMalaysia(latitude, longitude)) {
        if (mounted) {
          _showMessage(
            'The emulator GPS is outside Malaysia. Open Emulator Extended '
            'Controls > Location and set a Penang location, for example '
            '5.4141, 100.3288, or test with a real phone.',
          );
        }
        return;
      }

      final placeName = await _geocodingService.getPlaceName(
        latitude,
        longitude,
      );
      final nearestStop = _repository.findNearestStop(latitude, longitude);
      if (!mounted) return;
      final gpsLocation = JourneyLocation(
        name: placeName ??
            (nearestStop == null
                ? 'Current location'
                : 'Near ${nearestStop.name}'),
        latitude: latitude,
        longitude: longitude,
      );

      setState(() {
        _originLocation = gpsLocation;
        _originController.text = gpsLocation.name;
      });
      if (nearestStop != null) {
        _showMessage(
          'GPS selected. Nearest transport stop: ${nearestStop.name}',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('Unable to get current location: $error');
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  void _openJourneyOnMap(JourneyOption option) {
    setState(() {
      _activeJourney = option;
      _mapKey = UniqueKey();
      _selectedIndex = 2;
    });
  }

  Future<void> _addFavourite() async {
    final type = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('What do you want to save?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'Route'),
              child: const ListTile(
                leading: Icon(Icons.route),
                title: Text('Route'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'Stop'),
              child: const ListTile(
                leading: Icon(Icons.location_on_outlined),
                title: Text('Station or Stop'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'Journey'),
              child: const ListTile(
                leading: Icon(Icons.directions),
                title: Text('Saved Journey'),
              ),
            ),
          ],
        );
      },
    );
    if (type == null || !mounted) return;

    final choices = <_FavouriteChoice>[];
    if (type == 'Route') {
      for (final route in _repository.routes) {
        choices.add(
          _FavouriteChoice(
            title: route.number,
            subtitle: route.name,
            referenceId: route.id,
            type: 'Route',
          ),
        );
      }
    } else if (type == 'Stop') {
      for (final stop in _repository.stops) {
        choices.add(
          _FavouriteChoice(
            title: stop.name,
            subtitle: stop.accessible ? 'Accessible stop' : 'Transport stop',
            referenceId: stop.id,
            type: 'Stop',
          ),
        );
      }
    } else {
      for (final journey in _savedJourneys) {
        choices.add(
          _FavouriteChoice(
            title: '${journey.origin} -> ${journey.destination}',
            subtitle: journey.routeSummary,
            referenceId: journey.id,
            type: 'Journey',
          ),
        );
      }
    }

    if (choices.isEmpty) {
      _showMessage('Save a journey plan first before adding it as a favourite.');
      return;
    }

    final choice = await showDialog<_FavouriteChoice>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text('Select $type'),
          children: [
            SizedBox(
              width: double.maxFinite,
              height: 420,
              child: ListView.builder(
                itemCount: choices.length,
                itemBuilder: (context, index) {
                  final item = choices[index];
                  return ListTile(
                    leading: Icon(_favouriteIcon(item.type)),
                    title: Text(item.title),
                    subtitle: Text(item.subtitle),
                    onTap: () => Navigator.pop(dialogContext, item),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
    if (choice == null || !mounted) return;

    for (final favourite in _favourites) {
      if (favourite.type == choice.type &&
          favourite.referenceId == choice.referenceId) {
        _showMessage('This item is already in your favourites.');
        return;
      }
    }

    final category = await showDialog<FavouriteCategory>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Select a category'),
          children: _categories.map((item) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, item),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(item.colourValue),
                  radius: 10,
                ),
                title: Text(item.name),
              ),
            );
          }).toList(),
        );
      },
    );
    if (category == null) return;

    final favourite = FavouriteItem(
      id: 'favourite-${DateTime.now().microsecondsSinceEpoch}',
      title: choice.title,
      subtitle: choice.subtitle,
      type: choice.type,
      referenceId: choice.referenceId,
      categoryId: category.id,
      createdAt: DateTime.now(),
    );

    await _storage.addFavourite(favourite);
    await _fetchDashboardData();
    _showMessage('Favourite added to ${category.name}.');
  }

  Future<void> _manageFavourites() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const FavouriteManagerSheet(),
    );
    await _fetchDashboardData();
  }

  Future<void> _showSavedPlans() async {
    await showModalBottomSheet<SavedJourney>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const SavedJourneyManagerSheet(),
    );
    await _fetchDashboardData();
  }

  void _openFavourite(FavouriteItem favourite) {
    if (favourite.type == 'Stop') {
      _openPlanner(destination: favourite.title);
      return;
    }

    if (favourite.type == 'Journey') {
      for (final journey in _savedJourneys) {
        if (journey.id == favourite.referenceId) {
          _openPlanner(
            origin: journey.origin,
            destination: journey.destination,
            originLocation: journey.originLocation,
            destinationLocation: journey.destinationLocation,
          );
          return;
        }
      }
      _showMessage('This saved journey is no longer available.');
      return;
    }

    _changePage(2);
    _showMessage('${favourite.title} opened in the map module.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
          JourneyPlannerScreen(
            key: _plannerKey,
            initialOrigin: _originController.text,
            initialDestination: _destinationController.text,
            initialOriginLocation: _originLocation,
            initialDestinationLocation: _destinationLocation,
            onStartJourney: _openJourneyOnMap,
          ),
          TransitMapScreen(
            key: _mapKey,
            journey: _activeJourney,
          ),
          const TravelHistoryScreen(),
          const ProfileScreen(),
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
        IconButton(
          onPressed: _fetchDashboardData,
          tooltip: 'Refresh dashboard',
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildHomePage() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _fetchDashboardData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const Row(
            children: [
              Icon(Icons.location_on, color: AppTheme.primaryBlue),
              SizedBox(width: 6),
              Text(
                'Malaysia',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildJourneySearchCard(),
          const SizedBox(height: 22),
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
                onTap: () => _openPlanner(),
              ),
              _buildQuickAction(
                icon: Icons.map_outlined,
                label: 'Open Map',
                colour: const Color(0xFF00897B),
                onTap: () => _changePage(2),
              ),
              _buildQuickAction(
                icon: Icons.favorite_border,
                label: 'Add Favourite',
                colour: const Color(0xFFE91E63),
                onTap: _addFavourite,
              ),
              _buildQuickAction(
                icon: Icons.bookmarks_outlined,
                label: 'Saved Plans',
                colour: const Color(0xFFF57C00),
                onTap: _showSavedPlans,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(
            title: 'Upcoming Journey',
            actionText: 'See All',
            onAction: _showSavedPlans,
          ),
          const SizedBox(height: 12),
          _buildUpcomingJourney(),
          const SizedBox(height: 24),
          _buildSectionHeader(
            title: 'Favourites',
            actionText: 'Manage',
            onAction: _manageFavourites,
          ),
          const SizedBox(height: 10),
          _buildCategoryFilters(),
          const SizedBox(height: 12),
          _buildFavourites(),
          const SizedBox(height: 24),
          _buildSectionHeader(
            title: 'Recent Searches',
            actionText: 'Plan',
            onAction: () => _openPlanner(),
          ),
          const SizedBox(height: 10),
          _buildRecentSearches(),
          const SizedBox(height: 24),
          const Text(
            'Frequently Used Services',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _buildFrequentServices(),
          const SizedBox(height: 24),
          const Text(
            'Malaysia Public Transport Usage',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _buildPublicTransportRidership(),
          const SizedBox(height: 24),
          const Text(
            'Daily KTMB Usage',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _buildKtmbRidership(),
          const SizedBox(height: 24),
          _buildSectionHeader(
            title: 'Supported Live Status',
            actionText: 'View Map',
            onAction: () => _changePage(2),
          ),
          const SizedBox(height: 10),
          _buildLiveStatus(),
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
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _selectLocationFromMap(
                  controller: _originController,
                  title: 'Select origin on map',
                  isOrigin: true,
                ),
                tooltip: 'Select origin on map',
                icon: const Icon(
                  Icons.map_outlined,
                  color: AppTheme.primaryBlue,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _originController,
                  readOnly: true,
                  onTap: () => _selectLocationFromMap(
                    controller: _originController,
                    title: 'Select origin on map',
                    isOrigin: true,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Select origin',
                    filled: false,
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                onPressed: _gettingLocation ? null : _useGpsForOrigin,
                tooltip: 'Use current GPS location',
                icon: _gettingLocation
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
              IconButton(
                onPressed: _swapLocations,
                icon: const Icon(Icons.swap_vert),
              ),
            ],
          ),
          const Divider(height: 1),
          Row(
            children: [
              IconButton(
                onPressed: () => _selectLocationFromMap(
                  controller: _destinationController,
                  title: 'Select destination on map',
                  isOrigin: false,
                ),
                tooltip: 'Select destination on map',
                icon: const Icon(Icons.location_on, color: Colors.red),
              ),
              Expanded(
                child: TextField(
                  controller: _destinationController,
                  readOnly: true,
                  onTap: () => _selectLocationFromMap(
                    controller: _destinationController,
                    title: 'Select destination on map',
                    isOrigin: false,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Where do you want to go?',
                    filled: false,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () {
              if (_originLocation == null) {
                _showMessage('Please select an origin or use GPS.');
                return;
              }
              if (_destinationLocation == null) {
                _showMessage('Please select a destination on the map.');
                return;
              }
              _openPlanner(
                originLocation: _originLocation,
                destinationLocation: _destinationLocation,
              );
            },
            icon: const Icon(Icons.route),
            label: const Text('Plan Journey'),
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
              CircleAvatar(
                backgroundColor: colour.withValues(alpha: 0.12),
                child: Icon(icon, color: colour),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
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
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(onPressed: onAction, child: Text(actionText)),
      ],
    );
  }

  Widget _buildUpcomingJourney() {
    SavedJourney? upcoming;
    final now = DateTime.now();
    final futureJourneys = _savedJourneys.where((journey) {
      return journey.departureTime.isAfter(now);
    }).toList();
    futureJourneys.sort(
      (first, second) => first.departureTime.compareTo(second.departureTime),
    );
    if (futureJourneys.isNotEmpty) {
      upcoming = futureJourneys.first;
    }

    if (upcoming == null) {
      return _buildEmptyCard(
        icon: Icons.event_available,
        message: 'No upcoming journey. Save a future plan from Module 3.',
        buttonText: 'Plan Now',
        onPressed: () => _openPlanner(),
      );
    }
    final upcomingJourney = upcoming;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFE3F2FD),
                  child: Icon(Icons.directions, color: AppTheme.primaryBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${upcomingJourney.origin} -> ${upcomingJourney.destination}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_formatDate(upcomingJourney.departureTime)} at '
                        '${_formatTime(upcomingJourney.departureTime)}',
                        style: const TextStyle(
                          color: AppTheme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.bookmark, color: AppTheme.primaryBlue),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('${upcomingJourney.durationMinutes} min'),
                const SizedBox(width: 16),
                Text('RM ${upcomingJourney.fare.toStringAsFixed(2)}'),
                const Spacer(),
                TextButton(
                  onPressed: () => _openPlanner(
                    origin: upcomingJourney.origin,
                    destination: upcomingJourney.destination,
                    originLocation: upcomingJourney.originLocation,
                    destinationLocation: upcomingJourney.destinationLocation,
                  ),
                  child: const Text('View Journey'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: _selectedCategoryId == null,
              onSelected: (_) {
                setState(() => _selectedCategoryId = null);
              },
            ),
          ),
          for (final category in _categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: CircleAvatar(
                  radius: 6,
                  backgroundColor: Color(category.colourValue),
                ),
                label: Text(category.name),
                selected: _selectedCategoryId == category.id,
                onSelected: (_) {
                  setState(() => _selectedCategoryId = category.id);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFavourites() {
    final visibleFavourites = _favourites.where((item) {
      return _selectedCategoryId == null ||
          item.categoryId == _selectedCategoryId;
    }).toList();

    if (visibleFavourites.isEmpty) {
      return _buildEmptyCard(
        icon: Icons.favorite_border,
        message: 'No favourite in this category yet.',
        buttonText: 'Add Favourite',
        onPressed: _addFavourite,
      );
    }

    return SizedBox(
      height: 125,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visibleFavourites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final favourite = visibleFavourites[index];
          return InkWell(
            onTap: () => _openFavourite(favourite),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 155,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _favouriteIcon(favourite.type),
                    color: AppTheme.primaryBlue,
                  ),
                  const Spacer(),
                  Text(
                    favourite.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    favourite.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentSearches() {
    if (_recentSearches.isEmpty) {
      return _buildEmptyCard(
        icon: Icons.history,
        message: 'Your journey searches will appear here.',
      );
    }

    return Column(
      children: _recentSearches.take(3).map((search) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.history, color: AppTheme.primaryBlue),
            title: Text('${search.origin} -> ${search.destination}'),
            subtitle: Text(_formatDate(search.searchedAt)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPlanner(
              origin: search.origin,
              destination: search.destination,
              originLocation: search.originLocation,
              destinationLocation: search.destinationLocation,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFrequentServices() {
    if (_frequentServices.isEmpty) {
      return _buildEmptyCard(
        icon: Icons.bar_chart,
        message: 'Start journeys to build your frequently used services.',
      );
    }

    return Column(
      children: _frequentServices.map((service) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(_modeIcon(service.mode), size: 20),
            ),
            title: Text('${service.routeNumber} - ${service.routeName}'),
            subtitle: Text('${service.usageCount} journey uses'),
            trailing: Text(service.mode),
            onTap: () => _changePage(2),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPublicTransportRidership() {
    return FutureBuilder<List<PublicTransportRidership>>(
      future: _publicTransportRidership,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildApiLoadingCard('Loading public transport usage...');
        }

        if (snapshot.hasError) {
          return _buildApiErrorCard(
            'Unable to load public transport usage.',
            () {
              setState(() {
                _publicTransportRidership =
                    _ridershipApiService.fetchPublicTransportRidership();
              });
            },
          );
        }

        final records = snapshot.data ?? [];
        if (records.isEmpty) {
          return _buildApiMessageCard('No public transport usage is available.');
        }

        final latest = records.first;
        final services = latest.services.entries.where((entry) {
          return entry.value != null;
        }).toList();
        services.sort((first, second) {
          return second.value!.compareTo(first.value!);
        });

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Latest audited data: ${_formatApiDate(latest.date)}',
                  style: const TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                for (final service in services.take(5)) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.directions_transit,
                        color: AppTheme.primaryBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(service.key)),
                      Text(
                        '${service.value} trips',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                ],
                const Text(
                  'Source: data.gov.my, Prasarana and Ministry of Transport',
                  style: TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKtmbRidership() {
    return FutureBuilder<List<KtmbRidership>>(
      future: _ktmbRidership,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildApiLoadingCard('Loading daily KTMB usage...');
        }

        if (snapshot.hasError) {
          return _buildApiErrorCard(
            'Unable to load daily KTMB usage.',
            () {
              setState(() {
                _ktmbRidership = _ridershipApiService.fetchKtmbRidership();
              });
            },
          );
        }

        final records = snapshot.data ?? [];
        if (records.isEmpty) {
          return _buildApiMessageCard('No KTMB usage is available.');
        }

        final latestDate = records.first.date;
        final latestRecords = records.where((record) {
          return record.date == latestDate;
        }).toList();
        latestRecords.sort((first, second) {
          return second.ridership.compareTo(first.ridership);
        });

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data for ${_formatApiDate(latestDate)}',
                  style: const TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                for (final record in latestRecords) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.train,
                        color: Color(0xFF7B1FA2),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(record.serviceName)),
                      Text(
                        '${record.ridership} trips',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                ],
                const Text(
                  'Source: data.gov.my, KTMB and Ministry of Transport',
                  style: TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildApiLoadingCard(String message) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Widget _buildApiMessageCard(String message) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppTheme.secondaryText),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Widget _buildApiErrorCard(String message, VoidCallback onRetry) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  String _formatApiDate(String date) {
    final parts = date.split('-');
    if (parts.length != 3) return date;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  Widget _buildLiveStatus() {
    final liveRoutes = _repository.routes.where((route) {
      return route.liveSupported;
    }).take(3).toList();

    return Column(
      children: liveRoutes.map((route) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              _modeIcon(route.mode),
              color: _routeColour(route),
            ),
            title: Text('${route.number} - ${route.name}'),
            subtitle: Text('Every ${route.frequencyMinutes} min'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Live supported',
                style: TextStyle(fontSize: 10, color: Color(0xFF2E7D32)),
              ),
            ),
            onTap: () => _changePage(2),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyCard({
    required IconData icon,
    required String message,
    String? buttonText,
    VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.secondaryText),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          if (buttonText != null)
            TextButton(onPressed: onPressed, child: Text(buttonText)),
        ],
      ),
    );
  }
}

class FavouriteManagerSheet extends StatefulWidget {
  const FavouriteManagerSheet({super.key});

  @override
  State<FavouriteManagerSheet> createState() => _FavouriteManagerSheetState();
}

class _FavouriteManagerSheetState extends State<FavouriteManagerSheet> {
  final LocalStorageService _storage = LocalStorageService.instance;
  List<FavouriteCategory> _categories = [];
  List<FavouriteItem> _favourites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFavourites();
  }

  Future<void> _fetchFavourites() async {
    final categories = await _storage.getFavouriteCategories();
    final favourites = await _storage.getFavourites();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _favourites = favourites;
      _isLoading = false;
    });
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Category'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Category name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                controller.text.trim(),
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _storage.addFavouriteCategory(
      name: name,
      colourValue: 0xFF7B1FA2,
    );
    await _fetchFavourites();
  }

  Future<void> _renameCategory(FavouriteCategory category) async {
    final controller = TextEditingController(text: category.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename Category'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Category name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                controller.text.trim(),
              ),
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _storage.updateFavouriteCategory(category.copyWith(name: name));
    await _fetchFavourites();
  }

  Future<void> _deleteCategory(FavouriteCategory category) async {
    if (_categories.length == 1) {
      _showMessage('At least one category is required.');
      return;
    }
    await _storage.deleteFavouriteCategory(category.id);
    await _fetchFavourites();
  }

  Future<void> _moveFavourite(
    FavouriteItem favourite,
    String categoryId,
  ) async {
    await _storage.updateFavourite(
      favourite.copyWith(categoryId: categoryId),
    );
    await _fetchFavourites();
  }

  Future<void> _deleteFavourite(FavouriteItem favourite) async {
    await _storage.deleteFavourite(favourite.id);
    await _fetchFavourites();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Manage Favourites',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addCategory,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Category'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(
                          'Categories',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        for (final category in _categories)
                          Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 10,
                                backgroundColor: Color(category.colourValue),
                              ),
                              title: Text(category.name),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'rename') {
                                    _renameCategory(category);
                                  } else {
                                    _deleteCategory(category);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Rename'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        const Text(
                          'Favourite Items',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (_favourites.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'No favourites have been added.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        for (final favourite in _favourites)
                          Card(
                            child: ListTile(
                              leading: Icon(_favouriteIcon(favourite.type)),
                              title: Text(favourite.title),
                              subtitle: DropdownButton<String>(
                                value: favourite.categoryId,
                                isExpanded: true,
                                underline: const SizedBox(),
                                items: _categories.map((category) {
                                  return DropdownMenuItem<String>(
                                    value: category.id,
                                    child: Text(category.name),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    _moveFavourite(favourite, value);
                                  }
                                },
                              ),
                              trailing: IconButton(
                                onPressed: () => _deleteFavourite(favourite),
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
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

class _FavouriteChoice {
  const _FavouriteChoice({
    required this.title,
    required this.subtitle,
    required this.referenceId,
    required this.type,
  });

  final String title;
  final String subtitle;
  final String referenceId;
  final String type;
}

IconData _favouriteIcon(String type) {
  if (type == 'Route') return Icons.route;
  if (type == 'Stop') return Icons.location_on_outlined;
  return Icons.directions;
}

IconData _modeIcon(String mode) {
  if (mode == 'Bus') return Icons.directions_bus;
  if (mode == 'MRT') return Icons.subway;
  if (mode == 'LRT') return Icons.tram;
  if (mode == 'KTM') return Icons.train;
  if (mode == 'Monorail') return Icons.commute;
  return Icons.directions_transit;
}

Color _routeColour(TransitRoute route) {
  final hex = route.colourHex.replaceAll('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

String _formatTime(DateTime value) {
  var hour = value.hour;
  final period = hour >= 12 ? 'PM' : 'AM';
  if (hour == 0) hour = 12;
  if (hour > 12) hour -= 12;
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute $period';
}
