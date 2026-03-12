import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import '../blocs/analytics_bloc.dart';
import '../blocs/analytics_events.dart';
import '../blocs/analytics_state.dart';
import '../models/chart_data.dart';

class AnalyticsScreen extends StatelessJuiceWidget<AnalyticsBloc> {
  AnalyticsScreen({super.key})
      : super(groups: const {'analytics:charts', 'analytics:filters'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Date range filter
                SegmentedButton<DateRange>(
                  segments: const [
                    ButtonSegment(value: DateRange.week, label: Text('Week')),
                    ButtonSegment(value: DateRange.month, label: Text('Month')),
                    ButtonSegment(
                        value: DateRange.quarter, label: Text('Quarter')),
                    ButtonSegment(value: DateRange.year, label: Text('Year')),
                  ],
                  selected: {state.dateRange},
                  onSelectionChanged: (selected) {
                    bloc.send(FilterDataEvent(dateRange: selected.first));
                  },
                ),
                const SizedBox(height: 24),

                // Revenue chart
                Text('Revenue',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _BarChart(data: state.revenueData, color: Colors.green),
                const SizedBox(height: 32),

                // Users chart
                Text('New Users',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _BarChart(data: state.userData, color: Colors.blue),
              ],
            ),
    );
  }

  @override
  Widget close(BuildContext context) => const SizedBox.shrink();
}

/// Simple bar chart using containers (no chart library dependency).
class _BarChart extends StatelessWidget {
  final List<ChartData> data;
  final Color color;

  const _BarChart({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox(height: 200);

    final maxValue = data.map((d) => d.value).reduce(
        (a, b) => a > b ? a : b);

    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((d) {
          final fraction = maxValue > 0 ? d.value / maxValue : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    d.value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 150 * fraction,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.7),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(d.label, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
