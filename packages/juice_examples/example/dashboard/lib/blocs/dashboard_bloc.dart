import 'package:juice/juice.dart';
import 'dashboard_state.dart';
import 'dashboard_events.dart';
import 'use_cases/load_dashboard_use_case.dart';
import 'use_cases/refresh_stats_use_case.dart';

class DashboardBloc extends JuiceBloc<DashboardState> {
  DashboardBloc()
      : super(
          const DashboardState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadDashboardEvent,
                  useCaseGenerator: () => LoadDashboardUseCase(),
                  initialEventBuilder: () => LoadDashboardEvent(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: RefreshStatsEvent,
                  useCaseGenerator: () => RefreshStatsUseCase(),
                ),
          ],
        );
}
