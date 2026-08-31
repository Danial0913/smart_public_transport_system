import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/local_storage_service.dart';
import '../data/location_service.dart';
import '../data/transit_repository.dart';
import '../models/transit_models.dart';
import '../theme/app_theme.dart';
import 'supported_stop_map_picker.dart';

class JourneyPlannerScreen extends StatefulWidget {
  const JourneyPlannerScreen({
    super.key,
    this.initialOrigin = '',
    this.initialDestination = '',
    this.initialOriginLocation,
    this.initialDestinationLocation,
  });

  final String initialOrigin;
  final String initialDestination;
  final JourneyLocation? initialOriginLocation;
  final JourneyLocation? initialDestinationLocation;

  @override
  State<JourneyPlannerScreen> createState() => _JourneyPlannerScreenState();
}

class _JourneyPlannerScreenState extends State<JourneyPlannerScreen> {
  final TransitRepository _repository = TransitRepository.instance;
  final LocalStorageService _storage = LocalStorageService.instance;
  final LocationService _locationService = LocationService();

  late final TextEditingController _originController;
  late final TextEditingController _destinationController;
  JourneyLocation? _originLocation;
  JourneyLocation? _destinationLocation;

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _departAt = true;
  bool _accessibleOnly = false;
  bool _fewerTransfers = false;
  bool _loading = true;
  bool _searching = false;
  bool _gettingLocation = false;
  String? _loadError;
  double _maximumWalkingDistance = 2000;
  String _routePreference = 'Recommended';
  final Set<String> _selectedModes = {
    'Bus',
    'MRT',
    'LRT',
    'KTM',
    'Monorail',
  };
  List<JourneyOption> _routeResults = [];
  List<RecentSearch> _recentSearches = [];
  Set<String> _savedJourneyIds = {};

  @override
  void initState() {
    super.initState();
    _originController = TextEditingController(text: widget.initialOrigin);
    _destinationController = TextEditingController(
      text: widget.initialDestination,
    );
    _originLocation = widget.initialOriginLocation;
    _destinationLocation = widget.initialDestinationLocation;
    _loadData();
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      await _repository.load();
      await _storage.initialise();
      _originLocation ??= _locationFromStopName(_originController.text);
      _destinationLocation ??=
          _locationFromStopName(_destinationController.text);
      final recentSearches = await _storage.getRecentSearches();
      final savedJourneys = await _storage.getSavedJourneys();
      if (!mounted) return;
      setState(() {
        _recentSearches = recentSearches;
        _savedJourneyIds = savedJourneys.map((item) => item.id).toSet();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  void _swapLocations() {
    final origin = _originController.text;
    final originLocation = _originLocation;
    setState(() {
      _originController.text = _destinationController.text;
      _destinationController.text = origin;
      _originLocation = _destinationLocation;
      _destinationLocation = originLocation;
      _routeResults = [];
    });
  }

  JourneyLocation? _locationFromStopName(String name) {
    final stop = _repository.findStop(name);
    return stop == null ? null : JourneyLocation.fromStop(stop);
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedDate = selected);
  }

  Future<void> _selectTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedTime = selected);
  }

  Future<void> _chooseLocation({
    required TextEditingController controller,
    required String title,
    required bool isOrigin,
  }) async {
    final selectedLocation = await showModalBottomSheet<JourneyLocation>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SupportedStopMapPicker(
        title: title,
        stops: _repository.stops,
        initialLocation: isOrigin ? _originLocation : _destinationLocation,
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
      _routeResults = [];
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
          _showMessage('Location permission or GPS service is not available.');
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

      if (!mounted) return;
      final gpsLocation = JourneyLocation(
        name: 'Current location',
        latitude: latitude,
        longitude: longitude,
      );

      setState(() {
        _originController.text = gpsLocation.name;
        _originLocation = gpsLocation;
        _routeResults = [];
      });
      final nearestStop = _repository.findNearestStop(latitude, longitude);
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

  Future<void> _findRoutes() async {
    if (_searching) return;
    final originText = _originController.text.trim();
    final destinationText = _destinationController.text.trim();

    if (originText.isEmpty || destinationText.isEmpty) {
      _showMessage('Please enter an origin and destination.');
      return;
    }
    if (_selectedModes.isEmpty) {
      _showMessage('Please select at least one transport mode.');
      return;
    }

    final origin = _originLocation ?? _locationFromStopName(originText);
    final destination =
        _destinationLocation ?? _locationFromStopName(destinationText);
    if (origin == null || destination == null) {
      _showMessage('Select the origin and destination on the map.');
      return;
    }
    if (origin.latitude == destination.latitude &&
        origin.longitude == destination.longitude) {
      _showMessage('Origin and destination cannot be the same.');
      return;
    }

    setState(() => _searching = true);
    final requestedTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final routes = _repository.findJourneys(
      origin: origin,
      destination: destination,
      requestedTime: requestedTime,
      departAt: _departAt,
      selectedModes: _selectedModes,
      accessibleOnly: _accessibleOnly,
      fewerTransfers: _fewerTransfers,
      maximumWalkingMetres: _maximumWalkingDistance.round(),
      preference: _routePreference,
    );

    await _storage.recordSearch(
      origin: origin,
      destination: destination,
    );
    final recentSearches = await _storage.getRecentSearches();
    if (!mounted) return;
    setState(() {
      _originController.text = origin.name;
      _destinationController.text = destination.name;
      _originLocation = origin;
      _destinationLocation = destination;
      _routeResults = routes;
      _recentSearches = recentSearches;
      _searching = false;
    });

    if (routes.isEmpty) {
      _showMessage(
        'No route matches these filters. Try more modes or a longer walking distance.',
      );
    }
  }

  Future<void> _toggleSavedJourney(JourneyOption option) async {
    final isSaved = _savedJourneyIds.contains(option.id);
    if (isSaved) {
      await _storage.deleteSavedJourney(option.id);
    } else {
      await _storage.saveJourney(option);
    }
    if (!mounted) return;
    setState(() {
      if (isSaved) {
        _savedJourneyIds.remove(option.id);
      } else {
        _savedJourneyIds.add(option.id);
      }
    });
    _showMessage(isSaved ? 'Journey plan removed.' : 'Journey plan saved.');
  }

  Future<void> _startJourney(
    BuildContext bottomSheetContext,
    JourneyOption option,
  ) async {
    for (final leg in option.legs) {
      await _storage.recordServiceUse(leg.route);
    }
    if (!mounted || !bottomSheetContext.mounted) return;
    Navigator.pop(bottomSheetContext);
    _showMessage(
      'Journey started. ${option.routeSummary} was added to frequent services.',
    );
  }

  Future<void> _openSavedJourneyManager() async {
    final selected = await showModalBottomSheet<SavedJourney>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const SavedJourneyManagerSheet(),
    );

    final savedJourneys = await _storage.getSavedJourneys();
    if (!mounted) return;
    setState(() {
      _savedJourneyIds = savedJourneys.map((item) => item.id).toSet();
    });

    if (selected != null) {
      setState(() {
        _originController.text = selected.origin;
        _destinationController.text = selected.destination;
        _originLocation = selected.originLocation ??
            _locationFromStopName(selected.origin);
        _destinationLocation = selected.destinationLocation ??
            _locationFromStopName(selected.destination);
        _selectedDate = selected.departureTime;
        _selectedTime = TimeOfDay.fromDateTime(selected.departureTime);
      });
      await _findRoutes();
    }
  }

  void _showJourneyDetails(JourneyOption option) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (bottomSheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${option.origin.name} to ${option.destination.name}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatTime(option.departureTime)} - '
                  '${_formatTime(option.arrivalTime)}  |  '
                  '${option.totalDurationMinutes} min  |  '
                  'RM ${option.totalFare.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.secondaryText),
                ),
                const SizedBox(height: 16),
                JourneyRouteMap(option: option),
                const SizedBox(height: 20),
                const Text(
                  'Step-by-step instructions',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                for (int index = 0; index < option.directions.length; index++)
                  _buildDirectionStep(
                    number: index + 1,
                    description: option.directions[index],
                    isLast: index == option.directions.length - 1,
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(bottomSheetContext);
                          await _toggleSavedJourney(option);
                        },
                        icon: Icon(
                          _savedJourneyIds.contains(option.id)
                              ? Icons.bookmark_remove_outlined
                              : Icons.bookmark_add_outlined,
                        ),
                        label: Text(
                          _savedJourneyIds.contains(option.id)
                              ? 'Remove Plan'
                              : 'Save Plan',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _startJourney(
                          bottomSheetContext,
                          option,
                        ),
                        icon: const Icon(Icons.navigation),
                        label: const Text('Start Journey'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _buildErrorState();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Plan a Multimodal Journey',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: _openSavedJourneyManager,
              icon: const Icon(Icons.bookmarks_outlined),
              label: const Text('Saved Plans'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildLocationCard(),
        if (_recentSearches.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildRecentSearches(),
        ],
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
            onPressed: _searching ? null : _findRoutes,
            icon: _searching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(_searching ? 'Finding Routes...' : 'Find Routes'),
          ),
        ),
        if (_routeResults.isNotEmpty) ...[
          const SizedBox(height: 30),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Route Options',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Text('${_routeResults.length} found'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_originController.text} -> ${_destinationController.text}',
            style: const TextStyle(color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 14),
          for (int index = 0; index < _routeResults.length; index++) ...[
            _buildRouteOptionCard(
              _routeResults[index],
              recommended: index == 0,
            ),
            const SizedBox(height: 14),
          ],
          Text(
            'Routes use the offline teaching subset from '
            '${_repository.metadata['source']}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              'Transport data could not be loaded.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadData, child: const Text('Try Again')),
          ],
        ),
      ),
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
          _buildLocationField(
            controller: _originController,
            label: 'Origin',
            hint: 'Enter starting location',
            icon: Icons.my_location,
            colour: AppTheme.primaryBlue,
            onChoose: () => _chooseLocation(
              controller: _originController,
              title: 'Select origin',
              isOrigin: true,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  tooltip: 'Swap locations',
                  icon: const Icon(
                    Icons.swap_vert,
                    color: AppTheme.primaryBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildLocationField(
            controller: _destinationController,
            label: 'Destination',
            hint: 'Where do you want to go?',
            icon: Icons.location_on,
            colour: Colors.red,
            onChoose: () => _chooseLocation(
              controller: _destinationController,
              title: 'Select destination',
              isOrigin: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color colour,
    required VoidCallback onChoose,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, color: colour),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            readOnly: true,
            onTap: onChoose,
            decoration: InputDecoration(labelText: label, hintText: hint),
          ),
        ),
        IconButton(
          onPressed: onChoose,
          tooltip: 'Choose any location on the map',
          icon: const Icon(Icons.map_outlined),
        ),
        ?trailing,
      ],
    );
  }

  Widget _buildRecentSearches() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Searches',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _recentSearches.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final search = _recentSearches[index];
              return ActionChip(
                avatar: const Icon(Icons.history, size: 16),
                label: Text('${search.origin} -> ${search.destination}'),
                onPressed: () {
                  final originLocation = search.originLocation ??
                      _locationFromStopName(search.origin);
                  final destinationLocation = search.destinationLocation ??
                      _locationFromStopName(search.destination);
                  setState(() {
                    _originController.text = search.origin;
                    _destinationController.text = search.destination;
                    _originLocation = originLocation;
                    _destinationLocation = destinationLocation;
                  });
                  _findRoutes();
                },
              );
            },
          ),
        ),
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
                onSelected: (_) => setState(() => _departAt = true),
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
                onSelected: (_) => setState(() => _departAt = false),
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
                label: _formatDate(_selectedDate),
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
        final colour = _modeColour(mode);
        return FilterChip(
          avatar: Icon(
            _modeIcon(mode),
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
          onSelected: (value) {
            setState(() {
              value ? _selectedModes.add(mode) : _selectedModes.remove(mode);
              _routeResults = [];
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildRoutePreferences() {
    const preferences = [
      'Recommended',
      'Fastest',
      'Lowest Fare',
      'Less Walking',
    ];

    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: preferences.map((preference) {
            return ChoiceChip(
              label: Text(preference),
              selected: _routePreference == preference,
              onSelected: (_) {
                setState(() {
                  _routePreference = preference;
                  _routeResults = [];
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _accessibleOnly,
                title: const Text('Accessible routes only'),
                subtitle: const Text('Use accessible vehicles and stops'),
                onChanged: (value) {
                  setState(() {
                    _accessibleOnly = value;
                    _routeResults = [];
                  });
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _fewerTransfers,
                title: const Text('Prefer fewer transfers'),
                subtitle: const Text('Prioritise simpler journeys'),
                onChanged: (value) {
                  setState(() {
                    _fewerTransfers = value;
                    _routeResults = [];
                  });
                },
              ),
              const Divider(),
              Row(
                children: [
                  const Expanded(child: Text('Maximum walking distance')),
                  Text('${_maximumWalkingDistance.round()} m'),
                ],
              ),
              Slider(
                min: 200,
                max: 10000,
                divisions: 49,
                value: _maximumWalkingDistance,
                label: '${_maximumWalkingDistance.round()} m',
                onChanged: (value) {
                  setState(() {
                    _maximumWalkingDistance = value;
                    _routeResults = [];
                  });
                },
              ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteOptionCard(
    JourneyOption option, {
    required bool recommended,
  }) {
    final isSaved = _savedJourneyIds.contains(option.id);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: recommended ? AppTheme.primaryBlue : AppTheme.border,
          width: recommended ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (recommended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Best match',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              const Spacer(),
              IconButton(
                onPressed: () => _toggleSavedJourney(option),
                tooltip: isSaved ? 'Remove saved plan' : 'Save plan',
                icon: Icon(
                  isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: AppTheme.primaryBlue,
                ),
              ),
            ],
          ),
          Text(
            option.routeSummary,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Depart ${_formatTime(option.departureTime)}  |  '
            'Arrive ${_formatTime(option.arrivalTime)}',
            style: const TextStyle(color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _buildMetric(Icons.schedule, '${option.totalDurationMinutes} min'),
              _buildMetric(
                Icons.payments_outlined,
                'RM ${option.totalFare.toStringAsFixed(2)}',
              ),
              _buildMetric(
                Icons.directions_walk,
                '${option.walkingMetres} m',
              ),
              _buildMetric(
                Icons.sync_alt,
                option.transferCount == 0
                    ? 'Direct'
                    : '${option.transferCount} transfer',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final leg in option.legs) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _routeColour(leg.route),
                  child: Icon(
                    _modeIcon(leg.route.mode),
                    size: 17,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              if (option.accessible)
                const Padding(
                  padding: EdgeInsets.only(left: 5),
                  child: Icon(Icons.accessible, color: Color(0xFF2E7D32)),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showJourneyDetails(option),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Details & Map'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: AppTheme.secondaryText),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12)),
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
              CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.primaryBlue,
                child: Text(
                  '$number',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AppTheme.border),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(description),
            ),
          ),
        ],
      ),
    );
  }
}

class SavedJourneyManagerSheet extends StatefulWidget {
  const SavedJourneyManagerSheet({super.key});

  @override
  State<SavedJourneyManagerSheet> createState() =>
      _SavedJourneyManagerSheetState();
}

class _SavedJourneyManagerSheetState extends State<SavedJourneyManagerSheet> {
  final LocalStorageService _storage = LocalStorageService.instance;
  final TransitRepository _repository = TransitRepository.instance;
  List<SavedJourney> _journeys = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    await _repository.load();
    final journeys = await _storage.getSavedJourneys();
    if (!mounted) return;
    setState(() {
      _journeys = journeys;
      _loading = false;
    });
  }

  Future<void> _editJourney(SavedJourney journey) async {
    final originController = TextEditingController(text: journey.origin);
    final destinationController = TextEditingController(text: journey.destination);
    JourneyLocation? originLocation = journey.originLocation;
    JourneyLocation? destinationLocation = journey.destinationLocation;
    final oldOriginStop = _repository.findStop(journey.origin);
    final oldDestinationStop = _repository.findStop(journey.destination);
    if (originLocation == null && oldOriginStop != null) {
      originLocation = JourneyLocation.fromStop(oldOriginStop);
    }
    if (destinationLocation == null && oldDestinationStop != null) {
      destinationLocation = JourneyLocation.fromStop(oldDestinationStop);
    }
    DateTime departure = journey.departureTime;

    final updated = await showDialog<SavedJourney>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Journey Plan'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: originController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Origin',
                        suffixIcon: Icon(Icons.map_outlined),
                      ),
                      onTap: () async {
                        final selected =
                            await showModalBottomSheet<JourneyLocation>(
                          context: dialogContext,
                          isScrollControlled: true,
                          builder: (_) => SupportedStopMapPicker(
                            title: 'Change origin',
                            stops: _repository.stops,
                            initialLocation: originLocation,
                          ),
                        );
                        if (selected == null) return;
                        setDialogState(() {
                          originLocation = selected;
                          originController.text = selected.name;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: destinationController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Destination',
                        suffixIcon: Icon(Icons.map_outlined),
                      ),
                      onTap: () async {
                        final selected =
                            await showModalBottomSheet<JourneyLocation>(
                          context: dialogContext,
                          isScrollControlled: true,
                          builder: (_) => SupportedStopMapPicker(
                            title: 'Change destination',
                            stops: _repository.stops,
                            initialLocation: destinationLocation,
                          ),
                        );
                        if (selected == null) return;
                        setDialogState(() {
                          destinationLocation = selected;
                          destinationController.text = selected.name;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event),
                        title: Text(_formatDate(departure)),
                        subtitle: Text(_formatTime(departure)),
                        trailing: const Icon(Icons.edit_calendar),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: dialogContext,
                            initialDate: departure,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 1),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (date == null || !dialogContext.mounted) return;
                          final time = await showTimePicker(
                            context: dialogContext,
                            initialTime: TimeOfDay.fromDateTime(departure),
                          );
                          if (time == null) return;
                          setDialogState(() {
                            departure = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final selectedOrigin = originLocation;
                    final selectedDestination = destinationLocation;
                    if (selectedOrigin == null || selectedDestination == null) {
                      return;
                    }
                    Navigator.pop(
                      dialogContext,
                      journey.copyWith(
                        origin: selectedOrigin.name,
                        destination: selectedDestination.name,
                        originLatitude: selectedOrigin.latitude,
                        originLongitude: selectedOrigin.longitude,
                        destinationLatitude: selectedDestination.latitude,
                        destinationLongitude: selectedDestination.longitude,
                        departureTime: departure,
                      ),
                    );
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );

    originController.dispose();
    destinationController.dispose();
    if (updated == null) return;
    await _storage.updateSavedJourney(updated);
    await _reload();
  }

  Future<void> _duplicateJourney(SavedJourney journey) async {
    await _storage.duplicateSavedJourney(journey);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Journey plan duplicated for the next day.')),
    );
  }

  Future<void> _deleteJourney(SavedJourney journey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Journey Plan?'),
        content: Text('${journey.origin} to ${journey.destination} will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.deleteSavedJourney(journey.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Saved Journey Plans',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(Icons.swipe_left, color: AppTheme.secondaryText),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _journeys.isEmpty
                      ? const _EmptySavedJourneyState()
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _journeys.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final journey = _journeys[index];
                            return Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${journey.origin} -> ${journey.destination}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              _editJourney(journey);
                                            } else if (value == 'duplicate') {
                                              _duplicateJourney(journey);
                                            } else if (value == 'delete') {
                                              _deleteJourney(journey);
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Edit'),
                                            ),
                                            PopupMenuItem(
                                              value: 'duplicate',
                                              child: Text('Duplicate'),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${journey.routeSummary}  |  '
                                      '${journey.durationMinutes} min  |  '
                                      'RM ${journey.fare.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppTheme.secondaryText,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${_formatDate(journey.departureTime)} at '
                                      '${_formatTime(journey.departureTime)}',
                                    ),
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () => Navigator.pop(context, journey),
                                        icon: const Icon(Icons.route),
                                        label: const Text('Use This Plan'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySavedJourneyState extends StatelessWidget {
  const _EmptySavedJourneyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmarks_outlined, size: 52, color: AppTheme.secondaryText),
            SizedBox(height: 12),
            Text('No saved plans yet', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text(
              'Find a route and tap the bookmark button to save it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

class JourneyRouteMap extends StatelessWidget {
  const JourneyRouteMap({super.key, required this.option});

  final JourneyOption option;

  @override
  Widget build(BuildContext context) {
    final allStops = option.legs.expand((leg) => leg.stops).toList();
    double totalLatitude = option.origin.latitude + option.destination.latitude;
    double totalLongitude =
        option.origin.longitude + option.destination.longitude;
    for (final stop in allStops) {
      totalLatitude += stop.latitude;
      totalLongitude += stop.longitude;
    }
    final pointCount = allStops.length + 2;
    final mapCentre = LatLng(
      totalLatitude / pointCount,
      totalLongitude / pointCount,
    );

    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: mapCentre,
          initialZoom: 10,
        ),
        children: [
          TileLayer(
            maxZoom: 19,
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'my.edu.tarumt.smart_tublic_transport_system',
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: [
                  LatLng(option.origin.latitude, option.origin.longitude),
                  LatLng(
                    option.legs.first.from.latitude,
                    option.legs.first.from.longitude,
                  ),
                ],
                color: AppTheme.secondaryText,
                strokeWidth: 3,
              ),
              for (final leg in option.legs)
                Polyline(
                  points: leg.stops.map((stop) {
                    return LatLng(stop.latitude, stop.longitude);
                  }).toList(),
                  color: _routeColour(leg.route),
                  strokeWidth: 5,
                ),
              Polyline(
                points: [
                  LatLng(
                    option.legs.last.to.latitude,
                    option.legs.last.to.longitude,
                  ),
                  LatLng(
                    option.destination.latitude,
                    option.destination.longitude,
                  ),
                ],
                color: AppTheme.secondaryText,
                strokeWidth: 3,
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              for (final stop in allStops)
                Marker(
                  width: 32,
                  height: 32,
                  point: LatLng(stop.latitude, stop.longitude),
                  child: const Icon(
                    Icons.location_on,
                    color: AppTheme.primaryBlue,
                    size: 26,
                  ),
                ),
              Marker(
                width: 40,
                height: 40,
                point: LatLng(
                  option.origin.latitude,
                  option.origin.longitude,
                ),
                child: const Icon(
                  Icons.trip_origin,
                  color: Color(0xFF2E7D32),
                  size: 30,
                ),
              ),
              Marker(
                width: 40,
                height: 40,
                point: LatLng(
                  option.destination.latitude,
                  option.destination.longitude,
                ),
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 34,
                ),
              ),
            ],
          ),
          const Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.all(4),
              child: ColoredBox(
                color: Colors.white70,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
    );
  }
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

String _formatTime(DateTime value) {
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
          ? value.hour - 12
          : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

IconData _modeIcon(String mode) {
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

Color _modeColour(String mode) {
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

Color _routeColour(TransitRoute route) {
  final hex = route.colourHex.replaceAll('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}
