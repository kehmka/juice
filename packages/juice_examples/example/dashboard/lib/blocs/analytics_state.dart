import 'package:juice/juice.dart';
import '../models/chart_data.dart';

enum DateRange { week, month, quarter, year }

class AnalyticsState extends BlocState {
  final List<ChartData> revenueData;
  final List<ChartData> userData;
  final DateRange dateRange;
  final bool isLoading;

  const AnalyticsState({
    this.revenueData = const [],
    this.userData = const [],
    this.dateRange = DateRange.week,
    this.isLoading = false,
  });

  AnalyticsState copyWith({
    List<ChartData>? revenueData,
    List<ChartData>? userData,
    DateRange? dateRange,
    bool? isLoading,
  }) {
    return AnalyticsState(
      revenueData: revenueData ?? this.revenueData,
      userData: userData ?? this.userData,
      dateRange: dateRange ?? this.dateRange,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
