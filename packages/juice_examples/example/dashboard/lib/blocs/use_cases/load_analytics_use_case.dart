import 'package:juice/juice.dart';
import '../analytics_bloc.dart';
import '../analytics_events.dart';
import '../../models/chart_data.dart';

class LoadAnalyticsUseCase extends UseCase<AnalyticsBloc, LoadAnalyticsEvent> {
  @override
  Future<void> execute(LoadAnalyticsEvent event) async {
    emitWaiting(newState: bloc.state.copyWith(isLoading: true));
    await Future.delayed(const Duration(milliseconds: 500));

    emitUpdate(
      newState: bloc.state.copyWith(
        revenueData: ChartData.weeklyRevenue,
        userData: ChartData.monthlyUsers,
        isLoading: false,
      ),
    );
  }
}
