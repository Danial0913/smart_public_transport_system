import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/local_storage_service.dart';
import '../models/travel_history_models.dart';
import '../theme/app_theme.dart';

class TravelHistoryScreen extends StatefulWidget {
  const TravelHistoryScreen({super.key});

  @override
  State<TravelHistoryScreen> createState() {
    return _TravelHistoryScreenState();
  }
}

class _TravelHistoryScreenState extends State<TravelHistoryScreen> {
  final LocalStorageService _storage = LocalStorageService.instance;
  final List<String> _periods = const ['Today', 'This Week', 'This Month'];

  String _selectedPeriod = 'This Month';
  DateTime? _selectedMonth;
  final List<String> _monthNames = const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  List<CompletedJourney> _journeys = [];

  bool _loading = true;
  String? _error;

  double? _monthlyBudget;
  double _monthlySpending = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();

      final DateTime periodStart;
      final DateTime periodEnd;

      if (_selectedMonth != null) {
        periodStart = DateTime(
          _selectedMonth!.year,
          _selectedMonth!.month,
        );

        periodEnd = DateTime(
          _selectedMonth!.year,
          _selectedMonth!.month + 1,
        );
      } else {
        periodStart = _periodStart(now);

        if (_selectedPeriod == 'Today') {
          periodEnd = DateTime(
            now.year,
            now.month,
            now.day + 1,
          );
        } else if (_selectedPeriod == 'This Week') {
          periodEnd = now.add(const Duration(days: 1));
        } else {
          periodEnd = DateTime(now.year, now.month + 1);
        }
      }

      final journeys = await _storage.getCompletedJourneys(
        start: periodStart,
        end: periodEnd,
      );

      final budgetMonth = _selectedMonth ?? now;

      final monthStart = DateTime(
        budgetMonth.year,
        budgetMonth.month,
      );

      final nextMonth = DateTime(
        budgetMonth.year,
        budgetMonth.month + 1,
      );

      final monthJourneys = await _storage.getCompletedJourneys(
        start: monthStart,
        end: nextMonth,
      );

      final budget = await _storage.getMonthlyTravelBudget(
        budgetMonth,
      );

      var monthSpending = 0.0;

      for (final journey in monthJourneys) {
        monthSpending += journey.fare;
      }

      if (!mounted) return;

      setState(() {
        _journeys = journeys;
        _monthlyBudget = budget;
        _monthlySpending = monthSpending;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  DateTime _periodStart(DateTime now) {
    if (_selectedPeriod == 'Today') {
      return DateTime(now.year, now.month, now.day);
    }

    if (_selectedPeriod == 'This Week') {
      final startOfToday = DateTime(now.year, now.month, now.day);

      return startOfToday.subtract(Duration(days: now.weekday - 1));
    }

    return DateTime(now.year, now.month);
  }

  String get _selectedPeriodLabel {
    final selectedMonth = _selectedMonth;

    if (selectedMonth == null) {
      return _selectedPeriod;
    }

    return '${_monthNames[selectedMonth.month - 1]} '
        '${selectedMonth.year}';
  }
  double get _totalSpending {
    var total = 0.0;

    for (final journey in _journeys) {
      total += journey.fare;
    }

    return total;
  }

  int get _totalDuration {
    var total = 0;

    for (final journey in _journeys) {
      total += journey.durationMinutes;
    }

    return total;
  }

  double get _averageFare {
    if (_journeys.isEmpty) return 0;

    return _totalSpending / _journeys.length;
  }

  Map<String, int> get _routeCounts {
    final counts = <String, int>{};

    for (final journey in _journeys) {
      for (final leg in journey.legs) {
        counts[leg.routeNumber] = (counts[leg.routeNumber] ?? 0) + 1;
      }
    }

    return counts;
  }

  Map<String, int> get _modeCounts {
    final counts = <String, int>{};

    for (final journey in _journeys) {
      for (final leg in journey.legs) {
        counts[leg.mode] = (counts[leg.mode] ?? 0) + 1;
      }
    }

    return counts;
  }

  Map<String, int> get _stationCounts {
    final counts = <String, int>{};

    for (final journey in _journeys) {
      final stationsUsed = <String>{};

      for (final leg in journey.legs) {
        stationsUsed.add(leg.fromStopName);
        stationsUsed.add(leg.toStopName);
      }

      for (final station in stationsUsed) {
        counts[station] = (counts[station] ?? 0) + 1;
      }
    }

    return counts;
  }

  List<MapEntry<String, int>> _topEntries(
    Map<String, int> values, {
    int limit = 3,
  }) {
    final entries = values.entries.toList();

    entries.sort((first, second) {
      final countComparison = second.value.compareTo(first.value);

      if (countComparison != 0) {
        return countComparison;
      }

      return first.key.compareTo(second.key);
    });

    return entries.take(limit).toList();
  }

  Future<void> _selectPeriod(String period) async {
    setState(() {
      _selectedPeriod = period;
      _selectedMonth = null;
    });

    await _loadHistory();
  }
  Future<void> _selectHistoryMonth() async {
    final now = DateTime.now();
    final initialMonth = _selectedMonth ?? now;

    var selectedMonthNumber = initialMonth.month;
    var selectedYear = initialMonth.year;

    final selectedDate = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            final years = List<int>.generate(
              10,
                  (index) => now.year - index,
            );

            final maximumMonth =
            selectedYear == now.year ? now.month : 12;

            final months = List<int>.generate(
              maximumMonth,
                  (index) => index + 1,
            );

            return AlertDialog(
              title: const Text('Select Month'),
              content: SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedMonthNumber,
                      decoration: const InputDecoration(
                        labelText: 'Month',
                        border: OutlineInputBorder(),
                      ),
                      items: months.map((month) {
                        return DropdownMenuItem<int>(
                          value: month,
                          child: Text(_monthNames[month - 1]),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;

                        dialogSetState(() {
                          selectedMonthNumber = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: selectedYear,
                      decoration: const InputDecoration(
                        labelText: 'Year',
                        border: OutlineInputBorder(),
                      ),
                      items: years.map((year) {
                        return DropdownMenuItem<int>(
                          value: year,
                          child: Text('$year'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;

                        dialogSetState(() {
                          selectedYear = value;

                          if (selectedYear == now.year &&
                              selectedMonthNumber > now.month) {
                            selectedMonthNumber = now.month;
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      DateTime(
                        selectedYear,
                        selectedMonthNumber,
                      ),
                    );
                  },
                  child: const Text('View History'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedDate == null || !mounted) return;

    setState(() {
      _selectedMonth = selectedDate;
      _selectedPeriod = 'Selected Month';
    });

    await _loadHistory();
  }
  Future<void> _setBudget() async {
    final budgetFormKey = GlobalKey<FormState>();
    final budgetMonth = _selectedMonth ?? DateTime.now();
    var budgetText =
        _monthlyBudget?.toStringAsFixed(2) ?? '';

    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Set Monthly Budget'),
          content: Form(
            key: budgetFormKey,
            child: TextFormField(
              initialValue: budgetText,
              keyboardType:
              const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Budget amount',
                prefixText: 'RM ',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                budgetText = value;
              },
              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty) {
                  return 'Please enter a budget amount.';
                }

                final enteredAmount =
                double.tryParse(value.trim());

                if (enteredAmount == null) {
                  return 'Please enter a valid amount.';
                }

                if (enteredAmount <= 0) {
                  return 'Budget must be more than RM0.';
                }

                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!budgetFormKey.currentState!
                    .validate()) {
                  return;
                }

                final enteredAmount = double.parse(
                  budgetText.trim(),
                );

                Navigator.pop(
                  dialogContext,
                  enteredAmount,
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (amount == null || !mounted) {
      return;
    }

    try {
      await _storage.setMonthlyTravelBudget(
        month: budgetMonth,
        amount: amount,
      );

      if (!mounted) {
        return;
      }

      await _loadHistory();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Monthly budget updated successfully.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to save budget: $error',
          ),
        ),
      );
    }
  }

  Future<void> _deleteJourney(CompletedJourney journey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Travel Record?'),
          content: Text(
            '${journey.origin} to '
            '${journey.destination}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _storage.deleteCompletedJourney(journey.id);

    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'Unable to load travel history',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadHistory,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: AppTheme.background,
      child: RefreshIndicator(
        onRefresh: _loadHistory,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildPeriodSelector(),
            const SizedBox(height: 18),
            _buildSummary(),
            const SizedBox(height: 18),
            _buildBudgetCard(),
            const SizedBox(height: 18),
            _buildSpendingChart(),
            const SizedBox(height: 18),
            _buildTransportUsage(),
            const SizedBox(height: 18),
            _buildFrequentRoutes(),
            const SizedBox(height: 18),
            _buildFrequentStations(),
            const SizedBox(height: 18),
            _buildHistoryList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'History & Analytics',
          style: TextStyle(
            color: AppTheme.mainText,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Completed journeys and transport expenses',
          style: TextStyle(color: AppTheme.secondaryText),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    final periodWidgets = <Widget>[];

    for (final period in _periods) {
      final selected =
          _selectedMonth == null &&
              period == _selectedPeriod;

      periodWidgets.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(period),
            selected: selected,
            onSelected: (_) {
              _selectPeriod(period);
            },
          ),
        ),
      );
    }

    final selectedMonthText = _selectedMonth == null
        ? 'Select Month'
        : '${_monthNames[_selectedMonth!.month - 1]} '
        '${_selectedMonth!.year}';

    periodWidgets.add(
      ChoiceChip(
        avatar: const Icon(
          Icons.calendar_month_outlined,
          size: 18,
        ),
        label: Text(selectedMonthText),
        selected: _selectedMonth != null,
        onSelected: (_) {
          _selectHistoryMonth();
        },
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: periodWidgets),
    );
  }

  Widget _buildSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Travel Summary',
          style: TextStyle(
            color: AppTheme.mainText,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.45,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            _buildSummaryCard(
              title: 'Total Trips',
              value: '${_journeys.length}',
              icon: Icons.route,
              colour: AppTheme.primaryBlue,
            ),
            _buildSummaryCard(
              title: 'Total Spending',
              value: 'RM${_totalSpending.toStringAsFixed(2)}',
              icon: Icons.payments_outlined,
              colour: const Color(0xFFF57C00),
            ),
            _buildSummaryCard(
              title: 'Average Fare',
              value: 'RM${_averageFare.toStringAsFixed(2)}',
              icon: Icons.calculate_outlined,
              colour: const Color(0xFF00897B),
            ),
            _buildSummaryCard(
              title: 'Travel Time',
              value: _formatDuration(_totalDuration),
              icon: Icons.schedule,
              colour: const Color(0xFF7B1FA2),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color colour,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colour),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: colour,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetCard() {
    final budget = _monthlyBudget;

    final progress = budget == null || budget <= 0
        ? 0.0
        : (_monthlySpending / budget).clamp(0.0, 1.0).toDouble();

    final remaining = budget == null
        ? 0.0
        : math.max(0, budget - _monthlySpending);

    final exceeded = budget != null && _monthlySpending > budget;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Monthly Transport Budget',
                    style: TextStyle(
                      color: AppTheme.mainText,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _setBudget,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(budget == null ? 'Set' : 'Edit'),
                ),
              ],
            ),
            if (budget == null)
              const Text(
                'No monthly budget has been set.',
                style: TextStyle(color: AppTheme.secondaryText),
              )
            else ...[
              Text(
                'RM${_monthlySpending.toStringAsFixed(2)} '
                'of RM${budget.toStringAsFixed(2)} used',
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                borderRadius: BorderRadius.circular(8),
                color: exceeded ? Colors.red : AppTheme.primaryBlue,
              ),
              const SizedBox(height: 8),
              Text(
                exceeded
                    ? 'Budget exceeded by '
                          'RM${(_monthlySpending - budget).toStringAsFixed(2)}'
                    : 'RM${remaining.toStringAsFixed(2)} remaining',
                style: TextStyle(
                  color: exceeded ? Colors.red : AppTheme.secondaryText,
                  fontWeight: exceeded ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSpendingChart() {
    final points = _spendingPoints();

    var maximum = 0.0;

    for (final point in points) {
      maximum = math.max(maximum, point.amount);
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Expense Chart',
              style: TextStyle(
                color: AppTheme.mainText,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Spending for $_selectedPeriodLabel',
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 170,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: points.map((point) {
                  final barHeight = maximum == 0
                      ? 0.0
                      : (point.amount / maximum) * 105;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            point.amount == 0
                                ? '-'
                                : point.amount.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 9),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: math.max(3, barHeight),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            point.label,
                            maxLines: 1,
                            style: const TextStyle(
                              color: AppTheme.secondaryText,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_SpendingPoint> _spendingPoints() {
    if (_selectedPeriod == 'Today') {
      final values = <String, double>{
        'Morning': 0,
        'Afternoon': 0,
        'Evening': 0,
        'Night': 0,
      };

      for (final journey in _journeys) {
        final hour = journey.completedAt.hour;

        final label = hour < 12
            ? 'Morning'
            : hour < 17
            ? 'Afternoon'
            : hour < 21
            ? 'Evening'
            : 'Night';

        values[label] = values[label]! + journey.fare;
      }

      return values.entries.map((entry) {
        return _SpendingPoint(entry.key.substring(0, 3), entry.value);
      }).toList();
    }

    if (_selectedPeriod == 'This Week') {
      const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

      final values = List<double>.filled(7, 0);

      for (final journey in _journeys) {
        final index = journey.completedAt.weekday - 1;

        values[index] += journey.fare;
      }

      return List.generate(7, (index) {
        return _SpendingPoint(labels[index], values[index]);
      });
    }

    final values = List<double>.filled(5, 0);

    for (final journey in _journeys) {
      final weekIndex = ((journey.completedAt.day - 1) ~/ 7).clamp(0, 4);

      values[weekIndex] += journey.fare;
    }

    return List.generate(5, (index) {
      return _SpendingPoint('W${index + 1}', values[index]);
    });
  }

  Widget _buildTransportUsage() {
    final entries = _topEntries(_modeCounts, limit: 6);

    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);

    return _buildAnalyticsCard(
      title: 'Transport Usage',
      subtitle: 'Frequently used transport modes',
      child: entries.isEmpty
          ? const Text('No transport data yet.')
          : Column(
              children: entries.map((entry) {
                final percentage = total == 0 ? 0.0 : entry.value / total;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(_modeIcon(entry.key), color: _modeColour(entry.key)),
                      const SizedBox(width: 9),
                      SizedBox(width: 65, child: Text(entry.key)),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: percentage,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(6),
                          color: _modeColour(entry.key),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text('${entry.value}'),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildFrequentRoutes() {
    final routes = _topEntries(_routeCounts);

    return _buildRankingCard(
      title: 'Frequently Used Routes',
      icon: Icons.route,
      entries: routes,
    );
  }

  Widget _buildFrequentStations() {
    final stations = _topEntries(_stationCounts);

    return _buildRankingCard(
      title: 'Frequently Used Stations',
      icon: Icons.location_on_outlined,
      entries: stations,
    );
  }

  Widget _buildRankingCard({
    required String title,
    required IconData icon,
    required List<MapEntry<String, int>> entries,
  }) {
    return _buildAnalyticsCard(
      title: title,
      subtitle: 'Based on completed journeys',
      child: entries.isEmpty
          ? const Text('No journey data yet.')
          : Column(
              children: List.generate(entries.length, (index) {
                final entry = entries[index];

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(entry.key),
                  trailing: Text('${entry.value} trip(s)'),
                );
              }),
            ),
    );
  }

  Widget _buildAnalyticsCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.mainText,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 15),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Completed Journeys (${_journeys.length})',
          style: const TextStyle(
            color: AppTheme.mainText,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        if (_journeys.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: AppTheme.secondaryText,
                    ),
                    SizedBox(height: 10),
                    Text('No completed journeys yet.'),
                    SizedBox(height: 4),
                    Text(
                      'Complete a journey from the map '
                      'to record it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.secondaryText),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _journeys.length,
            separatorBuilder: (_, _) {
              return const SizedBox(height: 10);
            },
            itemBuilder: (context, index) {
              return _buildJourneyCard(_journeys[index]);
            },
          ),
      ],
    );
  }

  Widget _buildJourneyCard(CompletedJourney journey) {
    final firstMode = journey.legs.isEmpty ? 'Bus' : journey.legs.first.mode;

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _modeColour(firstMode).withValues(alpha: 0.12),
          child: Icon(_modeIcon(firstMode), color: _modeColour(firstMode)),
        ),
        title: Text(
          '${journey.origin} → '
          '${journey.destination}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_formatDate(journey.completedAt)} · '
          '${_formatTime(journey.completedAt)}',
        ),
        trailing: Text(
          'RM${journey.fare.toStringAsFixed(2)}',
          style: const TextStyle(
            color: Color(0xFFF57C00),
            fontWeight: FontWeight.bold,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              children: [
                const Divider(),
                _detailRow(Icons.route, 'Routes', journey.routeSummary),
                _detailRow(
                  Icons.schedule,
                  'Duration',
                  '${journey.durationMinutes} min',
                ),
                _detailRow(
                  Icons.directions_walk,
                  'Walking',
                  '${journey.walkingMetres} m',
                ),
                for (final leg in journey.legs)
                  _detailRow(
                    _modeIcon(leg.mode),
                    '${leg.mode} ${leg.routeNumber}',
                    '${leg.fromStopName} → '
                        '${leg.toStopName}',
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      _deleteJourney(journey);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppTheme.primaryBlue),
          const SizedBox(width: 9),
          SizedBox(
            width: 78,
            child: Text(
              title,
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.mainText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'Ferry':
        return Icons.directions_boat;
      case 'KTM':
      case 'MRT':
      case 'LRT':
      case 'Monorail':
        return Icons.train;
      default:
        return Icons.directions_bus;
    }
  }

  Color _modeColour(String mode) {
    switch (mode) {
      case 'Ferry':
        return const Color(0xFF00897B);
      case 'KTM':
        return const Color(0xFF3949AB);
      case 'MRT':
        return const Color(0xFFD32F2F);
      case 'LRT':
        return const Color(0xFFF9A825);
      case 'Monorail':
        return const Color(0xFF7B1FA2);
      default:
        return AppTheme.primaryBlue;
    }
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (hours == 0) {
      return '${remainingMinutes}m';
    }

    return '${hours}h ${remainingMinutes}m';
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${date.day} '
        '${months[date.month - 1]} '
        '${date.year}';
  }

  String _formatTime(DateTime date) {
    final period = date.hour >= 12 ? 'PM' : 'AM';

    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;

    final minute = date.minute.toString().padLeft(2, '0');

    return '$hour:$minute $period';
  }
}

class _SpendingPoint {
  const _SpendingPoint(this.label, this.amount);

  final String label;
  final double amount;
}
