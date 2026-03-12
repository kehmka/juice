import 'dart:math';
import 'package:juice/juice.dart';
import '../analytics_bloc.dart';
import '../analytics_events.dart';
import '../analytics_state.dart';
import '../../models/chart_data.dart';

class FilterDataUseCase extends UseCase<AnalyticsBloc, FilterDataEvent> {
  @override
  Future<void> execute(FilterDataEvent event) async {
    emitWaiting(newState: bloc.state.copyWith(
      dateRange: event.dateRange,
      isLoading: true,
    ));

    await Future.delayed(const Duration(milliseconds: 300));

    // Generate fake data based on date range
    final rand = Random(event.dateRange.index);
    final labels = _labelsFor(event.dateRange);
    final revenue = labels
        .map((l) => ChartData(
              label: l,
              value: 2000 + rand.nextInt(6000).toDouble(),
            ))
        .toList();
    final users = labels
        .map((l) => ChartData(
              label: l,
              value: 100 + rand.nextInt(400).toDouble(),
            ))
        .toList();

    emitUpdate(
      newState: bloc.state.copyWith(
        revenueData: revenue,
        userData: users,
        dateRange: event.dateRange,
        isLoading: false,
      ),
    );
  }

  List<String> _labelsFor(DateRange range) {
    switch (range) {
      case DateRange.week:
        return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      case DateRange.month:
        return ['W1', 'W2', 'W3', 'W4'];
      case DateRange.quarter:
        return ['Jan', 'Feb', 'Mar'];
      case DateRange.year:
        return ['Q1', 'Q2', 'Q3', 'Q4'];
    }
  }
}
