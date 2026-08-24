import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TravelHistoryScreen extends StatefulWidget {
  const TravelHistoryScreen({super.key});

  @override
  State<TravelHistoryScreen> createState() => _TravelHistoryScreenState();
}

class _TravelHistoryScreenState extends State<TravelHistoryScreen> {
  String _selectedPeriod = 'This Month';

  final List<String> _periods = ['This Week', 'This Month', 'This Year'];

  final List<TravelRecord> _travelRecords = const [
    TravelRecord(
      origin: 'KOMTAR Bus Terminal',
      destination: 'Queensbay Mall',
      date: '22 July 2026',
      time: '10:30 AM',
      transport: 'Bus 401E',
      duration: '35 min',
      expense: 2.70,
      icon: Icons.directions_bus,
      colour: AppTheme.primaryBlue,
    ),
    TravelRecord(
      origin: 'Butterworth Station',
      destination: 'Bukit Mertajam',
      date: '20 July 2026',
      time: '2:15 PM',
      transport: 'KTM Komuter',
      duration: '22 min',
      expense: 3.60,
      icon: Icons.train,
      colour: Color(0xFF7B1FA2),
    ),
    TravelRecord(
      origin: 'Raja Tun Uda Terminal',
      destination: 'Pangkalan Weld',
      date: '18 July 2026',
      time: '9:00 AM',
      transport: 'Penang Ferry',
      duration: '15 min',
      expense: 2.00,
      icon: Icons.directions_boat,
      colour: Color(0xFF00897B),
    ),
    TravelRecord(
      origin: 'KOMTAR',
      destination: 'Gurney Plaza',
      date: '16 July 2026',
      time: '5:40 PM',
      transport: 'Bus 103',
      duration: '28 min',
      expense: 2.00,
      icon: Icons.directions_bus,
      colour: AppTheme.primaryBlue,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: 18),
          _buildSectionTitle(
            title: 'Travel Summary',
            subtitle: 'Your public transport activity',
          ),
          const SizedBox(height: 12),
          _buildSummaryCards(),
          const SizedBox(height: 22),
          _buildExpenseChart(),
          const SizedBox(height: 22),
          _buildTransportBreakdown(),
          const SizedBox(height: 22),
          _buildHistoryHeader(),
          const SizedBox(height: 12),
          _buildTravelHistory(),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Travel Activity',
                style: TextStyle(
                  color: AppTheme.mainText,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Review your trips and transportation expenses.',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<String>(
          initialValue: _selectedPeriod,
          onSelected: (value) {
            setState(() {
              _selectedPeriod = value;
            });
          },
          itemBuilder: (context) {
            return _periods.map((period) {
              return PopupMenuItem<String>(value: period, child: Text(period));
            }).toList();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Text(
                  _selectedPeriod,
                  style: const TextStyle(
                    color: AppTheme.mainText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.keyboard_arrow_down, size: 18),
              ],
            ),
          ),
        ),
      ],
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

  Widget _buildSummaryCards() {
    return SizedBox(
      height: 120,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildSummaryCard(
            title: 'Total Trips',
            value: '24',
            unit: 'journeys',
            icon: Icons.route_outlined,
            colour: AppTheme.primaryBlue,
          ),
          _buildSummaryCard(
            title: 'Total Expenses',
            value: 'RM68.40',
            unit: 'this month',
            icon: Icons.account_balance_wallet_outlined,
            colour: const Color(0xFFF57C00),
          ),
          _buildSummaryCard(
            title: 'Travel Time',
            value: '12h 45m',
            unit: 'total duration',
            icon: Icons.schedule,
            colour: const Color(0xFF7B1FA2),
          ),
          _buildSummaryCard(
            title: 'CO₂ Saved',
            value: '8.6 kg',
            unit: 'estimated',
            icon: Icons.eco_outlined,
            colour: const Color(0xFF2E7D32),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color colour,
  }) {
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colour.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: colour, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  style: const TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
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
            unit,
            style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseChart() {
    final List<ExpenseData> expenses = [
      const ExpenseData('Week 1', 12.40),
      const ExpenseData('Week 2', 18.60),
      const ExpenseData('Week 3', 15.20),
      const ExpenseData('Week 4', 22.20),
    ];

    const double maximumExpense = 25;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Monthly Expenses',
                  style: TextStyle(
                    color: AppTheme.mainText,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(Icons.bar_chart, color: Color(0xFFF57C00)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Public transport spending by week',
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: expenses.map((expense) {
                final double barHeight =
                    (expense.amount / maximumExpense) * 105;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'RM${expense.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppTheme.mainText,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFFFA726), Color(0xFFF57C00)],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(7),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          expense.week,
                          style: const TextStyle(
                            color: AppTheme.secondaryText,
                            fontSize: 10,
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
    );
  }

  Widget _buildTransportBreakdown() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transport Usage',
            style: TextStyle(
              color: AppTheme.mainText,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Your most frequently used transport modes',
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
          ),
          SizedBox(height: 18),
          TransportUsageRow(
            title: 'Bus',
            percentage: 0.58,
            numberOfTrips: 14,
            icon: Icons.directions_bus,
            colour: AppTheme.primaryBlue,
          ),
          SizedBox(height: 15),
          TransportUsageRow(
            title: 'Train',
            percentage: 0.25,
            numberOfTrips: 6,
            icon: Icons.train,
            colour: Color(0xFF7B1FA2),
          ),
          SizedBox(height: 15),
          TransportUsageRow(
            title: 'Ferry',
            percentage: 0.17,
            numberOfTrips: 4,
            icon: Icons.directions_boat,
            colour: Color(0xFF00897B),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Recent Journeys',
            style: TextStyle(
              color: AppTheme.mainText,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Travel history filter selected')),
            );
          },
          icon: const Icon(Icons.filter_list, size: 18),
          label: const Text('Filter'),
        ),
      ],
    );
  }

  Widget _buildTravelHistory() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _travelRecords.length,
      separatorBuilder: (context, index) {
        return const SizedBox(height: 12);
      },
      itemBuilder: (context, index) {
        return _buildTravelRecordCard(_travelRecords[index]);
      },
    );
  }

  Widget _buildTravelRecordCard(TravelRecord record) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: record.colour.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(record.icon, color: record.colour),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  record.transport,
                  style: const TextStyle(
                    color: AppTheme.mainText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                'RM${record.expense.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFFF57C00),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Icon(Icons.circle, size: 12, color: record.colour),
                  Container(width: 2, height: 25, color: AppTheme.border),
                  const Icon(
                    Icons.location_on,
                    size: 17,
                    color: Color(0xFFD32F2F),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.origin,
                      style: const TextStyle(
                        color: AppTheme.mainText,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 19),
                    Text(
                      record.destination,
                      style: const TextStyle(
                        color: AppTheme.mainText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 25),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: AppTheme.secondaryText,
              ),
              const SizedBox(width: 5),
              Text(
                record.date,
                style: const TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.schedule,
                size: 14,
                color: AppTheme.secondaryText,
              ),
              const SizedBox(width: 5),
              Text(
                record.time,
                style: const TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                record.duration,
                style: TextStyle(
                  color: record.colour,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TransportUsageRow extends StatelessWidget {
  final String title;
  final double percentage;
  final int numberOfTrips;
  final IconData icon;
  final Color colour;

  const TransportUsageRow({
    super.key,
    required this.title,
    required this.percentage,
    required this.numberOfTrips,
    required this.icon,
    required this.colour,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: colour, size: 22),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.mainText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percentage,
              minHeight: 9,
              backgroundColor: colour.withOpacity(0.10),
              valueColor: AlwaysStoppedAnimation<Color>(colour),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          child: Text(
            '$numberOfTrips trips',
            textAlign: TextAlign.end,
            style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class TravelRecord {
  final String origin;
  final String destination;
  final String date;
  final String time;
  final String transport;
  final String duration;
  final double expense;
  final IconData icon;
  final Color colour;

  const TravelRecord({
    required this.origin,
    required this.destination,
    required this.date,
    required this.time,
    required this.transport,
    required this.duration,
    required this.expense,
    required this.icon,
    required this.colour,
  });
}

class ExpenseData {
  final String week;
  final double amount;

  const ExpenseData(this.week, this.amount);
}
