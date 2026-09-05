import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/geocoding_service.dart';
import '../data/ferry_api_service.dart';
import '../data/input_validator.dart';
import '../data/journey_notification_service.dart';
import '../data/local_storage_service.dart';
import '../data/location_service.dart';
import '../data/malaysia_time.dart';
import '../data/transit_repository.dart';
import '../models/accessibility_models.dart';
import '../models/transit_models.dart';
import '../models/travel_preferences.dart';
import '../theme/app_theme.dart';
import 'supported_stop_map_picker.dart';
import 'saved_places_widgets.dart';

class JourneyPlannerScreen extends StatefulWidget {
  const JourneyPlannerScreen({
    super.key,
    this.initialOrigin = '',
    this.initialDestination = '',
    this.initialOriginLocation,
    this.initialDestinationLocation,
    this.initialAccessibleOnly,
    this.initialSavedJourney,
    this.onStartJourney,
    this.storage,
  });

  final String initialOrigin;
  final String initialDestination;
  final JourneyLocation? initialOriginLocation;
  final JourneyLocation? initialDestinationLocation;
  final bool? initialAccessibleOnly;
  final SavedJourney? initialSavedJourney;
  final ValueChanged<JourneyOption>? onStartJourney;
  final LocalStorageService? storage;

  @override
  State<JourneyPlannerScreen> createState() => _JourneyPlannerScreenState();
}

class _JourneyPlannerScreenState extends State<JourneyPlannerScreen> {
  final TransitRepository _repository = TransitRepository.instance;
  LocalStorageService get _storage =>
      widget.storage ?? LocalStorageService.instance;
  final JourneyNotificationService _notifications =
      JourneyNotificationService.instance;
  final LocationService _locationService = LocationService();
  late final GeocodingService _geocodingService = GeocodingService();

  late final TextEditingController _originController;
  late final TextEditingController _destinationController;
  JourneyLocation? _originLocation;
  JourneyLocation? _destinationLocation;

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late bool _accessibleOnly;
  bool _fewerTransfers = false;
  bool _loading = true;
  bool _searching = false;
  bool _gettingLocation = false;
  bool _choosingLocation = false;
  bool _initialSavedJourneyHandled = false;
  String? _loadError;
  double _maximumWalkingDistance = 2000;
  String _routePreference = 'Recommended';
  final Set<String> _selectedModes = {
    'Bus',
    'MRT',
    'LRT',
    'KTM',
    'Monorail',
    'Ferry',
  };
  List<JourneyOption> _routeResults = [];
  List<RecentSearch> _recentSearches = [];
  Set<String> _savedJourneyIds = {};

  @override
  void initState() {
    super.initState();
    final initialDeparture = MalaysiaTime.defaultDeparture();
    _selectedDate = DateUtils.dateOnly(initialDeparture);
    _selectedTime = TimeOfDay.fromDateTime(initialDeparture);
    _originController = TextEditingController(text: widget.initialOrigin);
    _destinationController = TextEditingController(
      text: widget.initialDestination,
    );
    _originLocation = widget.initialOriginLocation;
    _destinationLocation = widget.initialDestinationLocation;
    _accessibleOnly = widget.initialAccessibleOnly ?? false;
    _loadData();
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      await _repository.load();
      await _storage.initialise();
      _originLocation ??= _locationFromStopName(_originController.text);
      _destinationLocation ??= _locationFromStopName(
        _destinationController.text,
      );
      final results = await Future.wait<Object?>([
        _storage.getRecentSearches(),
        _storage.getSavedJourneys(),
        if (widget.initialAccessibleOnly == null)
          _storage.getAccessibilityPreferences()
        else
          Future<Object?>.value(),
        _storage.getTravelPreferences(),
      ]);
      final recentSearches = results[0] as List<RecentSearch>;
      final savedJourneys = results[1] as List<SavedJourney>;
      final accessibilityPreferences = results[2] as AccessibilityPreferences?;
      final travelPreferences = results[3] as TravelPreferences;
      if (!mounted) return;
      setState(() {
        _selectedModes
          ..clear()
          ..addAll(travelPreferences.plannerModes);
        _maximumWalkingDistance = travelPreferences.maximumWalkingMetres
            .toDouble();
        _routePreference = travelPreferences.routePreference;
        _fewerTransfers = travelPreferences.preferFewerTransfers;
        if (accessibilityPreferences != null) {
          _accessibleOnly = accessibilityPreferences.accessibleRoutesOnly;
        }
        _recentSearches = recentSearches;
        _savedJourneyIds = savedJourneys.map((item) => item.id).toSet();
        _loading = false;
      });
      final initialSavedJourney = widget.initialSavedJourney;
      if (initialSavedJourney != null && !_initialSavedJourneyHandled) {
        _initialSavedJourneyHandled = true;
        await _useSavedJourney(initialSavedJourney, startImmediately: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Unable to prepare journey planning. Please try again.';
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
    final today = DateUtils.dateOnly(MalaysiaTime.now());
    final currentSelection = DateUtils.dateOnly(_selectedDate);
    final selected = await showDatePicker(
      context: context,
      initialDate: currentSelection.isBefore(today) ? today : currentSelection,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (selected == null || !mounted) return;
    final now = MalaysiaTime.now();
    final selectedDateTime = DateTime(
      selected.year,
      selected.month,
      selected.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    setState(() {
      _selectedDate = selected;
      if (selectedDateTime.isBefore(now)) {
        final nextAvailable = MalaysiaTime.nextDeparture();
        _selectedDate = DateUtils.dateOnly(nextAvailable);
        _selectedTime = TimeOfDay.fromDateTime(nextAvailable);
      }
    });
  }

  Future<void> _selectTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (selected == null || !mounted) return;
    final candidate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      selected.hour,
      selected.minute,
    );
    if (!MalaysiaTime.isWithinServiceHours(candidate)) {
      _showMessage('Choose a departure time between 5:00 AM and 11:59 PM.');
      return;
    }
    if (candidate.isBefore(
      MalaysiaTime.now().subtract(const Duration(minutes: 1)),
    )) {
      final nextAvailable = MalaysiaTime.nextDeparture();
      setState(() {
        _selectedDate = DateUtils.dateOnly(nextAvailable);
        _selectedTime = TimeOfDay.fromDateTime(nextAvailable);
      });
      _showMessage('Departure time must be now or in the future.');
      return;
    }
    setState(() => _selectedTime = selected);
  }

  Future<void> _chooseLocation({
    required TextEditingController controller,
    required String title,
    required bool isOrigin,
  }) async {
    if (_choosingLocation) return;
    _choosingLocation = true;
    try {
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
        _routeResults = [];
      });
    } finally {
      _choosingLocation = false;
    }
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
            'The reported GPS position is outside Malaysia. Choose a location on the map instead.',
          );
        }
        return;
      }

      final placeName = await _geocodingService.getPlaceName(
        latitude,
        longitude,
      );
      await _repository.ensureDataNear(latitude, longitude);
      final nearestStop = _repository.findNearestStop(latitude, longitude);
      if (!mounted) return;
      final gpsLocation = JourneyLocation(
        name:
            placeName ??
            (nearestStop == null
                ? 'Current location'
                : 'Near ${nearestStop.name}'),
        latitude: latitude,
        longitude: longitude,
      );

      setState(() {
        _originController.text = gpsLocation.name;
        _originLocation = gpsLocation;
        _routeResults = [];
      });
      if (nearestStop != null) {
        _showMessage(
          'GPS selected. Nearest transport stop: ${nearestStop.name}',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Unable to determine your location. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _findRoutes({bool startBestMatch = false}) async {
    if (_searching) return;
    final originText = _originController.text.trim();
    final destinationText = _destinationController.text.trim();

    if (originText.isEmpty || destinationText.isEmpty) {
      _showMessage('Please enter an origin and destination.');
      return;
    }
    final origin = _originLocation ?? _locationFromStopName(originText);
    final destination =
        _destinationLocation ?? _locationFromStopName(destinationText);
    final requestedTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final validationError = InputValidator.journey(
      origin: origin,
      destination: destination,
      requestedTime: requestedTime,
      modes: _selectedModes,
      maximumWalkingMetres: _maximumWalkingDistance,
    );
    if (validationError != null) {
      _showMessage(validationError);
      return;
    }
    final selectedOrigin = origin!;
    final selectedDestination = destination!;

    setState(() => _searching = true);

    // Allow Flutter to draw the loading indicator before route calculation.
    await Future<void>.delayed(Duration.zero);

    try {
      await _repository.ensureDataForJourney(
        selectedOrigin,
        selectedDestination,
        selectedModes: _selectedModes,
      );
      final routes = await _repository.findJourneys(
        origin: selectedOrigin,
        destination: selectedDestination,
        requestedTime: requestedTime,
        departAt: true,
        selectedModes: _selectedModes,
        accessibleOnly: _accessibleOnly,
        fewerTransfers: _fewerTransfers,
        maximumWalkingMetres: _maximumWalkingDistance.round(),
        preference: _routePreference,
      );

      if (routes.isNotEmpty) {
        await _storage.recordSearch(
          origin: selectedOrigin,
          destination: selectedDestination,
          requestedTime: requestedTime,
          preference: _routePreference,
        );
      }
      final recentSearches = await _storage.getRecentSearches();
      if (!mounted) return;
      setState(() {
        _originController.text = selectedOrigin.name;
        _destinationController.text = selectedDestination.name;
        _originLocation = selectedOrigin;
        _destinationLocation = selectedDestination;
        _routeResults = routes;
        _recentSearches = recentSearches;
      });

      if (routes.isEmpty) {
        _showMessage(
          'No route matches these locations and filters. Try increasing the walking limit or selecting another transport mode.',
        );
      } else {
        if (startBestMatch) {
          await _startJourneyOnMap(routes.first);
        } else {
          await _showRouteResults();
        }
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Unable to calculate this route. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _showRouteResults() async {
    if (_routeResults.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.88,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_routeResults.length} Route Options',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_originController.text} to '
                                '${_destinationController.text}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _routeResults.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        return _buildRouteOptionCard(
                          _routeResults[index],
                          recommended: index == 0,
                          onSavedChanged: () {
                            if (sheetContext.mounted) {
                              setSheetState(() {});
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleSavedJourney(JourneyOption option) async {
    final isSaved = _savedJourneyIds.contains(option.id);
    JourneyReminderResult? reminderResult;
    try {
      if (isSaved) {
        await _storage.deleteSavedJourney(option.id);
        await _notifications.cancelJourney(option.id);
      } else {
        await _storage.saveJourney(
          option,
          preference: _routePreference,
          departAt: true,
          maximumWalkingMetres: _maximumWalkingDistance.round(),
          accessibleOnly: _accessibleOnly,
          fewerTransfers: _fewerTransfers,
        );
        reminderResult = await _notifications.scheduleJourney(
          journeyId: option.id,
          origin: option.origin.name,
          destination: option.destination.name,
          departureTime: option.departureTime,
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Unable to update this saved plan. Please try again.');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      if (isSaved) {
        _savedJourneyIds.remove(option.id);
      } else {
        _savedJourneyIds.add(option.id);
      }
    });
    _showMessage(
      isSaved
          ? 'Journey plan and departure reminder removed.'
          : _savedReminderMessage(reminderResult!),
    );
  }

  Future<void> _startJourney(
    BuildContext bottomSheetContext,
    JourneyOption option,
  ) async {
    if (!await _recordJourneyStart(option)) return;
    if (!mounted || !bottomSheetContext.mounted) return;
    Navigator.pop(bottomSheetContext, true);
  }

  Future<bool> _recordJourneyStart(JourneyOption option) async {
    try {
      for (final leg in option.legs) {
        await _storage.recordServiceUse(leg.route);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Unable to start this journey. Please try again.');
      }
      return false;
    }
    return true;
  }

  Future<void> _startJourneyOnMap(JourneyOption option) async {
    if (!await _recordJourneyStart(option) || !mounted) return;
    final openOnMap = widget.onStartJourney;
    if (openOnMap != null) {
      openOnMap(option);
    } else {
      _showMessage(
        'Journey started. ${option.routeSummary} was added to frequent services.',
      );
    }
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
      await _useSavedJourney(selected, startImmediately: true);
    }
  }

  Future<void> _useSavedJourney(
    SavedJourney selected, {
    required bool startImmediately,
  }) async {
    final now = MalaysiaTime.now();
    final selectedDeparture =
        selected.departureTime.isBefore(
              now.subtract(const Duration(minutes: 1)),
            ) ||
            !MalaysiaTime.isWithinServiceHours(selected.departureTime)
        ? MalaysiaTime.nextDeparture()
        : selected.departureTime;
    if (!mounted) return;
    setState(() {
      _originController.text = selected.origin;
      _destinationController.text = selected.destination;
      _originLocation =
          selected.originLocation ?? _locationFromStopName(selected.origin);
      _destinationLocation =
          selected.destinationLocation ??
          _locationFromStopName(selected.destination);
      _selectedDate = DateUtils.dateOnly(selectedDeparture);
      _selectedTime = TimeOfDay.fromDateTime(selectedDeparture);
      _routePreference = selected.preference == 'Lowest Fee'
          ? 'Lowest Fee'
          : selected.preference;
      _maximumWalkingDistance = selected.maximumWalkingMetres.toDouble().clamp(
        200,
        10000,
      );
      _accessibleOnly = selected.accessibleOnly;
      _fewerTransfers = selected.fewerTransfers;
      if (selected.modes.isNotEmpty) {
        _selectedModes
          ..clear()
          ..addAll(selected.modes);
      }
    });
    await _findRoutes(startBestMatch: startImmediately);
  }

  Future<void> _showJourneyDetails(JourneyOption option) async {
    final started = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (bottomSheetContext) => _JourneyDetailsSheet(
        option: option,
        initiallySaved: _savedJourneyIds.contains(option.id),
        onToggleSaved: () => _toggleSavedJourney(option),
        onStart: () => _startJourney(bottomSheetContext, option),
      ),
    );

    if (started != true || !mounted) return;

    // Close the route-options popup underneath the journey-details popup.
    Navigator.pop(context);
    final openOnMap = widget.onStartJourney;
    if (openOnMap != null) {
      openOnMap(option);
    } else {
      _showMessage(
        'Journey started. ${option.routeSummary} was added to frequent services.',
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _showRouteResults,
            icon: const Icon(Icons.route),
            label: Text('View ${_routeResults.length} Route Options'),
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
          SavedPlaceSelector(
            settings: _storage,
            label: 'Use saved place as origin',
            onSelected: (location) => setState(() {
              _originLocation = location;
              _originController.text = location.name;
              _routeResults = [];
            }),
          ),
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
          SavedPlaceSelector(
            settings: _storage,
            label: 'Use saved place as destination',
            onSelected: (location) => setState(() {
              _destinationLocation = location;
              _destinationController.text = location.name;
              _routeResults = [];
            }),
          ),
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
                  final originLocation =
                      search.originLocation ??
                      _locationFromStopName(search.origin);
                  final destinationLocation =
                      search.destinationLocation ??
                      _locationFromStopName(search.destination);
                  final now = MalaysiaTime.now();
                  final requested =
                      search.requestedTime != null &&
                          search.requestedTime!.isAfter(now) &&
                          MalaysiaTime.isWithinServiceHours(
                            search.requestedTime!,
                          )
                      ? search.requestedTime!
                      : MalaysiaTime.nextDeparture();
                  setState(() {
                    _originController.text = search.origin;
                    _destinationController.text = search.destination;
                    _originLocation = originLocation;
                    _destinationLocation = destinationLocation;
                    _selectedDate = requested;
                    _selectedTime = TimeOfDay.fromDateTime(requested);
                    if (search.preference != null) {
                      _routePreference = search.preference == 'Lowest Fee'
                          ? 'Lowest Fee'
                          : search.preference!;
                    }
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
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Select departure date and time',
            style: TextStyle(color: AppTheme.secondaryText),
          ),
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
    const modes = ['Bus', 'MRT', 'LRT', 'KTM', 'Monorail', 'Ferry'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
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
                  value
                      ? _selectedModes.add(mode)
                      : _selectedModes.remove(mode);
                  _routeResults = [];
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        const Text(
          'Penang Ferry map geometry comes from the government MyGeoMap service; operating times and fee follow Penang Port Commission.',
          style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
        ),
      ],
    );
  }

  Widget _buildRoutePreferences() {
    const preferences = [
      'Recommended',
      'Fastest',
      'Lowest Fee',
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
    VoidCallback? onSavedChanged,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                onPressed: () async {
                  await _toggleSavedJourney(option);
                  onSavedChanged?.call();
                },
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
          if (!option.usesOfficialSchedule) ...[
            const SizedBox(height: 4),
            const Text(
              'Route available · times are estimated because no matching scheduled trip was published.',
              style: TextStyle(
                color: Color(0xFFE65100),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _buildMetric(
                Icons.schedule,
                '${option.totalDurationMinutes} min',
              ),
              _buildMetric(Icons.payments_outlined, _feeText(option)),
              _buildMetric(Icons.directions_walk, '${option.walkingMetres} m'),
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
}

class _JourneyDetailsSheet extends StatefulWidget {
  const _JourneyDetailsSheet({
    required this.option,
    required this.initiallySaved,
    required this.onToggleSaved,
    required this.onStart,
  });

  final JourneyOption option;
  final bool initiallySaved;
  final Future<void> Function() onToggleSaved;
  final Future<void> Function() onStart;

  @override
  State<_JourneyDetailsSheet> createState() => _JourneyDetailsSheetState();
}

class _JourneyDetailsSheetState extends State<_JourneyDetailsSheet> {
  late bool _saved;

  @override
  void initState() {
    super.initState();
    _saved = widget.initiallySaved;
  }

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${option.origin.name} to ${option.destination.name}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close details',
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatTime(option.departureTime)} - '
              '${_formatTime(option.arrivalTime)}  |  '
              '${option.totalDurationMinutes} min  |  ${_feeText(option)}',
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
            const SizedBox(height: 4),
            Text(
              'Modes: ${option.modes.join(', ')}',
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
            if (!option.usesOfficialSchedule) ...[
              const SizedBox(height: 6),
              const Text(
                'This route is based on the official stop sequence, but its displayed times are estimates.',
                style: TextStyle(color: Color(0xFFE65100), fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            JourneyRouteMap(option: option),
            const SizedBox(height: 20),
            const Text(
              'Step-by-step instructions',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < option.directions.length; index++)
              _journeyDirectionStep(
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
                      await widget.onToggleSaved();
                      if (mounted) setState(() => _saved = !_saved);
                    },
                    icon: Icon(
                      _saved
                          ? Icons.bookmark_remove_outlined
                          : Icons.bookmark_add_outlined,
                    ),
                    label: Text(_saved ? 'Remove Plan' : 'Save Plan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.onStart,
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
  }
}

Widget _journeyDirectionStep({
  required int number,
  required String description,
  required bool isLast,
}) {
  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 34,
          child: Column(
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
                Expanded(child: Container(width: 2, color: AppTheme.border)),
            ],
          ),
        ),
        const SizedBox(width: 10),
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

class SavedJourneyManagerSheet extends StatefulWidget {
  const SavedJourneyManagerSheet({super.key, this.upcomingOnly = false});

  final bool upcomingOnly;

  @override
  State<SavedJourneyManagerSheet> createState() =>
      _SavedJourneyManagerSheetState();
}

class _SavedJourneyManagerSheetState extends State<SavedJourneyManagerSheet> {
  final LocalStorageService _storage = LocalStorageService.instance;
  final TransitRepository _repository = TransitRepository.instance;
  final JourneyNotificationService _notifications =
      JourneyNotificationService.instance;
  List<SavedJourney> _journeys = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      await _repository.load();
      var journeys = await _storage.getSavedJourneys();
      if (widget.upcomingOnly) {
        final now = MalaysiaTime.now();
        journeys =
            journeys
                .where((journey) => journey.departureTime.isAfter(now))
                .toList()
              ..sort(
                (first, second) =>
                    first.departureTime.compareTo(second.departureTime),
              );
      }
      if (!mounted) return;
      setState(() {
        _journeys = journeys;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Unable to load saved plans. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _editJourney(SavedJourney journey) async {
    final originController = TextEditingController(text: journey.origin);
    final destinationController = TextEditingController(
      text: journey.destination,
    );
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
    final now = MalaysiaTime.now();
    DateTime departure = journey.departureTime.isBefore(now)
        ? MalaysiaTime.nextDeparture()
        : journey.departureTime;
    if (!MalaysiaTime.isWithinServiceHours(departure)) {
      departure = MalaysiaTime.nextDeparture();
    }

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
                        final selected = await Navigator.push<JourneyLocation>(
                          dialogContext,
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => SupportedStopMapPicker(
                              title: 'Change origin',
                              stops: _repository.stops,
                              initialLocation: originLocation,
                            ),
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
                        final selected = await Navigator.push<JourneyLocation>(
                          dialogContext,
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => SupportedStopMapPicker(
                              title: 'Change destination',
                              stops: _repository.stops,
                              initialLocation: destinationLocation,
                            ),
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
                            initialDate: DateUtils.dateOnly(departure),
                            firstDate: DateUtils.dateOnly(MalaysiaTime.now()),
                            lastDate: DateUtils.dateOnly(
                              MalaysiaTime.now(),
                            ).add(const Duration(days: 365)),
                          );
                          if (date == null || !dialogContext.mounted) return;
                          final time = await showTimePicker(
                            context: dialogContext,
                            initialTime: TimeOfDay.fromDateTime(departure),
                          );
                          if (time == null) return;
                          final candidate = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                          if (!MalaysiaTime.isWithinServiceHours(candidate)) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Choose a departure time between 5:00 AM and 11:59 PM.',
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                          setDialogState(() {
                            departure = candidate;
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
                    final validationError = InputValidator.journey(
                      origin: selectedOrigin,
                      destination: selectedDestination,
                      requestedTime: departure,
                      modes: journey.modes.isEmpty
                          ? const {'Bus'}
                          : journey.modes.toSet(),
                      maximumWalkingMetres: journey.maximumWalkingMetres
                          .toDouble(),
                    );
                    if (validationError != null) {
                      ScaffoldMessenger.of(
                        dialogContext,
                      ).showSnackBar(SnackBar(content: Text(validationError)));
                      return;
                    }
                    Navigator.pop(
                      dialogContext,
                      journey.copyWith(
                        origin: selectedOrigin!.name,
                        destination: selectedDestination!.name,
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
    final recalculated = await _recalculateJourney(updated);
    if (recalculated == null) return;
    final saved = await _savePlanChange(() async {
      await _storage.updateSavedJourney(recalculated);
      await _scheduleReminder(recalculated);
    });
    if (!saved) return;
    await _reload();
  }

  Future<void> _duplicateJourney(SavedJourney journey) async {
    final tomorrow = journey.departureTime.add(const Duration(days: 1));
    final duplicatedDeparture =
        tomorrow.isBefore(MalaysiaTime.now()) ||
            !MalaysiaTime.isWithinServiceHours(tomorrow)
        ? MalaysiaTime.nextDeparture()
        : tomorrow;
    final request = journey.copyWith(
      id: '${journey.id}-copy-${MalaysiaTime.now().microsecondsSinceEpoch}',
      departureTime: duplicatedDeparture,
      savedAt: MalaysiaTime.now(),
    );
    final recalculated = await _recalculateJourney(request);
    if (recalculated == null) return;
    final saved = await _savePlanChange(() async {
      await _storage.updateSavedJourney(recalculated);
      await _scheduleReminder(recalculated);
    });
    if (!saved) return;
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Journey plan duplicated for the next day.'),
      ),
    );
  }

  Future<SavedJourney?> _recalculateJourney(SavedJourney request) async {
    final origin = request.originLocation;
    final destination = request.destinationLocation;
    if (origin == null || destination == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This plan has incomplete locations.')),
        );
      }
      return null;
    }
    final modes = request.modes.toSet();
    if (modes.isEmpty) {
      modes.addAll(['Bus', 'MRT', 'LRT', 'KTM', 'Monorail', 'Ferry']);
    }
    try {
      await _repository.ensureDataForJourney(
        origin,
        destination,
        selectedModes: modes,
      );
      final options = await _repository.findJourneys(
        origin: origin,
        destination: destination,
        requestedTime: request.departureTime,
        departAt: true,
        selectedModes: modes,
        accessibleOnly: request.accessibleOnly,
        fewerTransfers: request.fewerTransfers,
        maximumWalkingMetres: request.maximumWalkingMetres,
        preference: request.preference,
      );
      if (options.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No current official schedule matches this plan.'),
            ),
          );
        }
        return null;
      }
      return SavedJourney.fromOption(
        options.first,
        id: request.id,
        savedAt: request.savedAt,
        preference: request.preference,
        departAt: true,
        maximumWalkingMetres: request.maximumWalkingMetres,
        accessibleOnly: request.accessibleOnly,
        fewerTransfers: request.fewerTransfers,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to refresh this plan. Please try again.'),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _deleteJourney(SavedJourney journey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Journey Plan?'),
        content: Text(
          '${journey.origin} to ${journey.destination} will be removed.',
        ),
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
    final deleted = await _savePlanChange(() async {
      await _storage.deleteSavedJourney(journey.id);
      await _notifications.cancelJourney(journey.id);
    });
    if (!deleted) return;
    await _reload();
  }

  Future<bool> _savePlanChange(Future<void> Function() operation) async {
    try {
      await operation();
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update saved plans. Please try again.'),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _scheduleReminder(SavedJourney journey) async {
    final result = await _notifications.scheduleJourney(
      journeyId: journey.id,
      origin: journey.origin,
      destination: journey.destination,
      departureTime: journey.departureTime,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_savedReminderMessage(result))));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.upcomingOnly
                          ? 'Upcoming Journeys'
                          : 'Saved Journey Plans',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.swipe_left, color: AppTheme.secondaryText),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 44),
                            const SizedBox(height: 10),
                            Text(_loadError!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _reload,
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _journeys.isEmpty
                  ? _EmptySavedJourneyState(upcomingOnly: widget.upcomingOnly)
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
                                  '${journey.knownFare == null ? 'Fee unavailable' : 'Fee RM ${journey.knownFare!.toStringAsFixed(2)}'}',
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
                                    onPressed: () =>
                                        Navigator.pop(context, journey),
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
  const _EmptySavedJourneyState({required this.upcomingOnly});

  final bool upcomingOnly;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bookmarks_outlined,
              size: 52,
              color: AppTheme.secondaryText,
            ),
            const SizedBox(height: 12),
            Text(
              upcomingOnly ? 'No upcoming journeys' : 'No saved plans yet',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              upcomingOnly
                  ? 'Save a journey with a future departure time to see it here.'
                  : 'Find a route and tap the bookmark button to save it.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.secondaryText),
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
    final hasFerry = option.legs.any((leg) => leg.route.mode == 'Ferry');
    if (!hasFerry) return _buildMap(const []);

    // The government API is requested only when a user opens a ferry map.
    return FutureBuilder<List<TransitPoint>>(
      future: FerryApiService.instance.loadPenangRoute(),
      builder: (context, snapshot) {
        final governmentRoute = snapshot.data ?? const <TransitPoint>[];
        final sourceText = snapshot.hasError
            ? 'Government ferry map unavailable. Showing the saved terminal route.'
            : snapshot.hasData
            ? 'Route geometry: MyGeoMap · Schedule and fee: Penang Port Commission'
            : 'Loading government ferry route...';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMap(governmentRoute),
            const SizedBox(height: 6),
            Text(
              sourceText,
              style: const TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 11,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMap(List<TransitPoint> governmentFerryRoute) {
    final allStops = option.legs.expand((leg) => leg.stops).toList();
    final markerStopsById = <String, TransitStop>{};
    for (final leg in option.legs) {
      markerStopsById[leg.from.id] = leg.from;
      markerStopsById[leg.to.id] = leg.to;
    }
    final markerStops = markerStopsById.values.toList();
    final mapPoints = <LatLng>[
      LatLng(option.origin.latitude, option.origin.longitude),
      for (final stop in allStops) LatLng(stop.latitude, stop.longitude),
      LatLng(option.destination.latitude, option.destination.longitude),
    ];
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
          initialZoom: 12,
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(mapPoints),
            padding: const EdgeInsets.all(28),
            maxZoom: 15,
          ),
        ),
        children: [
          TileLayer(
            maxZoom: 19,
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'my.edu.tarumt.smart_public_transport_system',
            panBuffer: 0,
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
                  points: _pointsForLeg(leg, governmentFerryRoute),
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
              for (final stop in markerStops)
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
                point: LatLng(option.origin.latitude, option.origin.longitude),
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

  List<LatLng> _pointsForLeg(
    JourneyLeg leg,
    List<TransitPoint> governmentFerryRoute,
  ) {
    if (leg.route.mode == 'Ferry' && governmentFerryRoute.length >= 2) {
      final route = governmentFerryRoute
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();
      final firstDistance = _coordinateDistance(route.first, leg.from);
      final lastDistance = _coordinateDistance(route.last, leg.from);
      return lastDistance < firstDistance ? route.reversed.toList() : route;
    }
    if (leg.shapePoints.isNotEmpty) {
      return leg.shapePoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();
    }
    return leg.stops
        .map((stop) => LatLng(stop.latitude, stop.longitude))
        .toList();
  }

  double _coordinateDistance(LatLng point, TransitStop stop) {
    final latitude = point.latitude - stop.latitude;
    final longitude = point.longitude - stop.longitude;
    return latitude * latitude + longitude * longitude;
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

String _feeText(JourneyOption option) {
  final officialFee = option.knownTotalFare;
  if (officialFee == null) {
    return 'Fee unavailable';
  }
  return 'Fee RM ${officialFee.toStringAsFixed(2)}';
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
    case 'Ferry':
      return Icons.directions_boat;
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
    case 'Ferry':
      return const Color(0xFF00897B);
    default:
      return AppTheme.secondaryText;
  }
}

Color _routeColour(TransitRoute route) {
  final hex = route.colourHex.replaceAll('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}

String _savedReminderMessage(JourneyReminderResult result) {
  return switch (result) {
    JourneyReminderResult.disabled =>
      'Journey plan saved. Travel notifications are turned off in your profile.',
    JourneyReminderResult.scheduledExact =>
      'Journey plan saved. A reminder will appear at departure time.',
    JourneyReminderResult.scheduledInexact =>
      'Journey plan saved. Enable exact alarms for an exact-time reminder.',
    JourneyReminderResult.shownNow =>
      'Journey plan saved. The journey starts now.',
    JourneyReminderResult.permissionDenied =>
      'Journey plan saved, but notification permission was not granted.',
    JourneyReminderResult.failed =>
      'Journey plan saved, but its departure reminder could not be scheduled.',
  };
}
