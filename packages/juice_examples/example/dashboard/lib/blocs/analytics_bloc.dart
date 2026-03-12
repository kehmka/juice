import 'package:juice/juice.dart';
import 'analytics_state.dart';
import 'analytics_events.dart';
import 'use_cases/load_analytics_use_case.dart';
import 'use_cases/filter_data_use_case.dart';

class AnalyticsBloc extends JuiceBloc<AnalyticsState> {
  AnalyticsBloc()
      : super(
          const AnalyticsState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadAnalyticsEvent,
                  useCaseGenerator: () => LoadAnalyticsUseCase(),
                  initialEventBuilder: () => LoadAnalyticsEvent(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: FilterDataEvent,
                  useCaseGenerator: () => FilterDataUseCase(),
                ),
          ],
        );
}
