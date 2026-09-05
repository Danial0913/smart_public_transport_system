import 'package:flutter/material.dart';

import '../../data/accessibility_service.dart';
import '../../models/accessibility_models.dart';
import '../../theme/app_theme.dart';
import 'accessibility_comparison_screen.dart';
import 'accessibility_station_detail_screen.dart';
import 'accessibility_ui.dart';

class AccessibilityStationResultsScreen extends StatefulWidget {
  const AccessibilityStationResultsScreen({
    super.key,
    required this.region,
    required this.query,
    required this.requiredFacilities,
    this.searchLoader,
  });

  final AccessibilityRegion region;
  final String query;
  final Set<AccessibilityFacility> requiredFacilities;
  final Future<AccessibilityStationSearch> Function()? searchLoader;

  @override
  State<AccessibilityStationResultsScreen> createState() =>
      _AccessibilityStationResultsScreenState();
}

class _AccessibilityStationResultsScreenState
    extends State<AccessibilityStationResultsScreen> {
  static const accessibilityTeal = Color(0xFF00897B);
  static const _pageSize = 100;

  final _scrollController = ScrollController();
  final Set<String> _comparisonIds = {};
  final List<StationAccessibility> _stations = [];
  AccessibilityStationSearch? _search;
  bool _loading = true;
  bool _appending = false;
  String? _error;
  int _loadVersion = 0;

  bool get _hasMore => _stations.length < (_search?.totalCount ?? 0);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool preserveCount = false}) async {
    final version = ++_loadVersion;
    final count = preserveCount && _stations.isNotEmpty
        ? _stations.length
        : _pageSize;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final search =
          await (widget.searchLoader?.call() ??
              AccessibilityService.instance.searchStations(
                region: widget.region,
                query: widget.query,
                requiredFacilities: widget.requiredFacilities,
              ));
      if (!mounted || version != _loadVersion) return;
      final stations = search.page(offset: 0, limit: count);
      setState(() {
        _search = search;
        _stations
          ..clear()
          ..addAll(stations);
        final ids = stations.map((station) => station.stop.id).toSet();
        _comparisonIds.removeWhere((id) => !ids.contains(id));
        _loading = false;
      });
      if (!preserveCount && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter <= 0) _loadMore();
  }

  void _loadMore() {
    if (_loading || _appending || !_hasMore) return;
    setState(() {
      _appending = true;
      _stations.addAll(
        _search!.page(offset: _stations.length, limit: _pageSize),
      );
    });
    // Wait for the new extent before accepting another bottom-of-list event.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _appending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Suitable Stops')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.region.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.query.trim().isNotEmpty)
                  Text('Search: ${widget.query.trim()}'),
                if (_search != null)
                  Text(
                    'Showing ${_stations.length} of ${_search!.totalCount} suitable stops',
                    key: const ValueKey('station-result-count'),
                  ),
                const SizedBox(height: 4),
                const Text(
                  'Only officially available facilities are shown. Select two stops to compare.',
                  style: TextStyle(color: AppTheme.secondaryText),
                ),
              ],
            ),
          ),
          if (_comparisonIds.isNotEmpty) _comparisonBar(),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                key: const PageStorageKey('accessibility-station-results'),
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _stations.length + 1,
                itemBuilder: (context, index) {
                  if (index < _stations.length) {
                    return _stationCard(_stations[index]);
                  }
                  return _footer();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    if (_error != null) {
      return Column(
        children: [
          const Text('Could not load stops. Please try again.'),
          Text(_error!, textAlign: TextAlign.center),
          TextButton(onPressed: _load, child: const Text('Try Again')),
        ],
      );
    }
    if (_loading) return const SizedBox(height: 40);
    if (_stations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'No matching stops. No official records confirm the selected facilities in this region. Try another region or change your facility filters.',
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_hasMore) {
      return TextButton(
        onPressed: _loadMore,
        child: const Text('Load next 100 stops'),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text('All matching stops loaded', textAlign: TextAlign.center),
    );
  }

  Widget _comparisonBar() {
    return Material(
      color: const Color(0xFFE0F2F1),
      child: ListTile(
        leading: const Icon(Icons.compare_arrows, color: accessibilityTeal),
        title: Text('${_comparisonIds.length} of 2 stations selected'),
        trailing: FilledButton(
          onPressed: _comparisonIds.length == 2 ? _compare : null,
          child: const Text('Compare'),
        ),
      ),
    );
  }

  void _toggleComparison(StationAccessibility station, bool selected) {
    if (selected && _comparisonIds.length == 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select exactly two stations to compare.'),
        ),
      );
      return;
    }
    setState(() {
      selected
          ? _comparisonIds.add(station.stop.id)
          : _comparisonIds.remove(station.stop.id);
    });
  }

  void _compare() {
    final selected = _stations
        .where((station) => _comparisonIds.contains(station.stop.id))
        .toList();
    if (selected.length != 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select exactly two stations to compare.'),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccessibilityComparisonScreen(
          first: selected[0],
          second: selected[1],
        ),
      ),
    );
  }

  Future<void> _openStation(StationAccessibility station) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AccessibilityStationDetailScreen(station: station),
      ),
    );
    if (mounted) await _load(preserveCount: true);
  }

  Widget _stationCard(StationAccessibility station) {
    final selected = _comparisonIds.contains(station.stop.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openStation(station),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (value) =>
                    _toggleComparison(station, value ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.stop.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: station.availableFacilities.map((facility) {
                        final status = station.facilities[facility]!;
                        return Tooltip(
                          message: '${facility.label}: ${status.label}',
                          child: Icon(
                            facility.icon,
                            size: 19,
                            color: status.colour,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
