import 'package:flutter/material.dart';

import '../../models/accessibility_models.dart';
import '../../theme/app_theme.dart';
import 'accessibility_ui.dart';

class AccessibilityComparisonScreen extends StatelessWidget {
  const AccessibilityComparisonScreen({
    super.key,
    required this.first,
    required this.second,
  });

  final StationAccessibility first;
  final StationAccessibility second;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Compare Accessibility')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Reported information can change. Check recent observations before travelling.',
              style: TextStyle(color: Color(0xFF00695C)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 132),
              Expanded(child: _stationHeading(first)),
              const SizedBox(width: 8),
              Expanded(child: _stationHeading(second)),
            ],
          ),
          const SizedBox(height: 10),
          ...AccessibilityFacility.values.map(
            (facility) => _comparisonRow(facility),
          ),
          const SizedBox(height: 18),
          _summaryCard(),
        ],
      ),
    );
  }

  Widget _stationHeading(StationAccessibility station) {
    return Text(
      station.stop.name,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.bold),
    );
  }

  Widget _comparisonRow(AccessibilityFacility facility) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  Icon(facility.icon, size: 20, color: const Color(0xFF00897B)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      facility.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _status(first.facilities[facility]!)),
            const SizedBox(width: 8),
            Expanded(child: _status(second.facilities[facility]!)),
          ],
        ),
      ),
    );
  }

  Widget _status(AccessibilityFacilityStatus status) {
    return Column(
      children: [
        Icon(status.icon, color: status.colour, size: 21),
        const SizedBox(height: 3),
        Text(
          status.label,
          textAlign: TextAlign.center,
          style: TextStyle(color: status.colour, fontSize: 10),
        ),
      ],
    );
  }

  Widget _summaryCard() {
    int score(StationAccessibility station) => station.facilities.values
        .where((status) => status == AccessibilityFacilityStatus.available)
        .length;
    final firstScore = score(first);
    final secondScore = score(second);
    final message = firstScore == secondScore
        ? 'Both stations have the same number of confirmed facilities.'
        : '${firstScore > secondScore ? first.stop.name : second.stop.name} has more confirmed facilities.';
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.balance_outlined)),
        title: const Text('Comparison summary'),
        subtitle: Text(message),
      ),
    );
  }
}
