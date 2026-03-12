import 'dart:math';
import 'package:juice/juice.dart';
import '../dashboard_bloc.dart';
import '../dashboard_events.dart';
import '../../models/dashboard_stats.dart';

class RefreshStatsUseCase extends UseCase<DashboardBloc, RefreshStatsEvent> {
  @override
  Future<void> execute(RefreshStatsEvent event) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final rand = Random();

    emitUpdate(
      newState: bloc.state.copyWith(
        stats: DashboardStats(
          totalUsers: 2847 + rand.nextInt(50),
          revenue: 48253.90 + rand.nextInt(1000),
          orders: 1293 + rand.nextInt(20),
          conversionRate: 3.0 + rand.nextDouble() * 0.5,
        ),
      ),
    );
  }
}
