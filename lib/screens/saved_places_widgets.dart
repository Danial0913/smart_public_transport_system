import 'package:flutter/material.dart';
import '../data/account_settings.dart';
import '../data/transit_repository.dart';
import '../data/travel_settings.dart';
import '../models/travel_preferences.dart';
import '../models/transit_models.dart';
import 'supported_stop_map_picker.dart';

typedef SavedPlaceLocationPicker =
    Future<JourneyLocation?> Function(
      BuildContext context,
      JourneyLocation? initial,
    );

class SavedPlacesCard extends StatefulWidget {
  const SavedPlacesCard({super.key, required this.settings, this.pickLocation});
  final TravelSettings settings;
  final SavedPlaceLocationPicker? pickLocation;
  @override
  State<SavedPlacesCard> createState() => _SavedPlacesCardState();
}

class _SavedPlacesCardState extends State<SavedPlacesCard> {
  List<SavedPlace> _places = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final places = await widget.settings.getSavedPlaces();
      if (mounted) setState(() => _places = places);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load saved places.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([SavedPlace? place]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SavedPlaceEditorScreen(
          settings: widget.settings,
          place: place,
          pickLocation: widget.pickLocation,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _remove(SavedPlace place) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${place.label}?'),
        content: const Text(
          'This place will be removed from your saved places and the planner selection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.settings.deletePlace(place.id);
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not remove this place. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          ListTile(
            title: Text(_error!),
            trailing: TextButton(onPressed: _load, child: const Text('Retry')),
          ),
        if (!_loading && _error == null && _places.isEmpty)
          const ListTile(
            title: Text('No saved places yet'),
            subtitle: Text(
              'Add home, work, or another destination to select it in Plan.',
            ),
          ),
        for (final place in _places)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(place.label),
            subtitle: Text(place.location.name),
            trailing: PopupMenuButton<String>(
              enabled: !_loading,
              tooltip: 'Manage ${place.label}',
              onSelected: (action) =>
                  action == 'edit' ? _edit(place) : _remove(place),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            ),
          ),
        ListTile(
          enabled: !_loading,
          leading: const Icon(Icons.add),
          title: const Text('Add Saved Place'),
          onTap: _loading ? null : () => _edit(),
        ),
      ],
    ),
  );
}

class SavedPlaceEditorScreen extends StatefulWidget {
  const SavedPlaceEditorScreen({
    super.key,
    required this.settings,
    this.place,
    this.pickLocation,
  });
  final TravelSettings settings;
  final SavedPlace? place;
  final SavedPlaceLocationPicker? pickLocation;
  @override
  State<SavedPlaceEditorScreen> createState() => _SavedPlaceEditorScreenState();
}

class _SavedPlaceEditorScreenState extends State<SavedPlaceEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _label = TextEditingController();
  JourneyLocation? _location;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _label.text = widget.place?.label ?? '';
    _location = widget.place?.location;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    setState(() => _busy = true);
    try {
      final location = widget.pickLocation != null
          ? await widget.pickLocation!(context, _location)
          : await Navigator.push<JourneyLocation>(
              context,
              MaterialPageRoute(
                builder: (_) => SupportedStopMapPicker(
                  title: 'Select saved place location',
                  stops: TransitRepository.instance.stops,
                  initialLocation: _location,
                ),
              ),
            );
      if (mounted && location != null) {
        setState(() {
          _location = location;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not select this location. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_location == null) {
      setState(() => _error = 'Select a location for this place.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.settings.savePlace(
        id: widget.place?.id,
        label: _label.text,
        location: _location!,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AccountSettingsException
              ? error.message
              : 'Could not save this place. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.place == null ? 'Add Saved Place' : 'Edit Saved Place',
      ),
    ),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              key: const ValueKey('saved-place-label'),
              controller: _label,
              enabled: !_busy,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: 'Place name',
                hintText: 'Home, work, university…',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a name for this place.'
                  : null,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(_location?.name ?? 'No location selected'),
              subtitle: const Text(
                'Choose the location used when planning your journey.',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _choose,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Choose Location'),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Please wait…' : 'Save Place'),
            ),
          ],
        ),
      ),
    ),
  );
}

class SavedPlaceSelector extends StatefulWidget {
  const SavedPlaceSelector({
    super.key,
    required this.settings,
    required this.label,
    required this.onSelected,
  });
  final TravelSettings settings;
  final String label;
  final ValueChanged<JourneyLocation> onSelected;
  @override
  State<SavedPlaceSelector> createState() => _SavedPlaceSelectorState();
}

class _SavedPlaceSelectorState extends State<SavedPlaceSelector> {
  bool _loading = false;
  Future<void> _select() async {
    setState(() => _loading = true);
    try {
      final places = await widget.settings.getSavedPlaces();
      if (!mounted) return;
      final place = await showModalBottomSheet<SavedPlace>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (places.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No saved places yet. Add a place from your Profile.',
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: places.length,
                  itemBuilder: (_, index) {
                    final place = places[index];
                    return ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(place.label),
                      subtitle: Text(place.location.name),
                      onTap: () => Navigator.pop(context, place),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
      if (mounted && place != null) widget.onSelected(place.location);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load saved places. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: _loading ? null : _select,
      icon: const Icon(Icons.bookmark_outline, size: 18),
      label: Text(_loading ? 'Loading saved places…' : widget.label),
    ),
  );
}
