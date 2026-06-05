import 'package:juice/juice.dart';

import '../analytics_bloc.dart';
import '../analytics_events.dart';
import '../analytics_state.dart';

/// Handles [InitializeAnalyticsEvent] — apply config and seed the consent flag.
class InitializeAnalyticsUseCase
    extends BlocUseCase<AnalyticsBloc, InitializeAnalyticsEvent> {
  @override
  Future<void> execute(InitializeAnalyticsEvent event) async {
    bloc.configure(event.config);
    emitUpdate(
      newState: bloc.state.copyWith(enabled: event.config.initiallyEnabled),
      groupsToRebuild: {AnalyticsGroups.status},
    );
  }
}
