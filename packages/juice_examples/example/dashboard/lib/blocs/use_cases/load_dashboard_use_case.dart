import 'package:juice/juice.dart';
import '../dashboard_bloc.dart';
import '../dashboard_events.dart';
import '../../models/dashboard_stats.dart';
import '../../models/user_activity.dart';

class LoadDashboardUseCase extends UseCase<DashboardBloc, LoadDashboardEvent> {
  @override
  Future<void> execute(LoadDashboardEvent event) async {
    emitWaiting(newState: bloc.state.copyWith(isLoading: true));

    // Simulate loading from backend
    await Future.delayed(const Duration(milliseconds: 600));

    emitUpdate(
      newState: bloc.state.copyWith(
        stats: DashboardStats.sample,
        recentActivity: UserActivity.samples,
        isLoading: false,
      ),
    );
  }
}
