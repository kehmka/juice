import 'package:juice/juice.dart';

import '../analytics_bloc.dart';
import '../analytics_events.dart';
import '../analytics_state.dart';

/// Handles [LogEventEvent] — fan an event out to the sinks, or drop it (counted)
/// when consent is off.
class LogEventUseCase extends BlocUseCase<AnalyticsBloc, LogEventEvent> {
  @override
  Future<void> execute(LogEventEvent event) async {
    if (!bloc.state.enabled) {
      emitUpdate(
        newState: bloc.state.copyWith(droppedCount: bloc.state.droppedCount + 1),
        groupsToRebuild: {AnalyticsGroups.status},
      );
      return;
    }

    await bloc.fanOut((s) => s.logEvent(event.name, event.params));
    emitUpdate(
      newState: bloc.state.copyWith(eventCount: bloc.state.eventCount + 1),
      groupsToRebuild: {AnalyticsGroups.status},
    );
  }
}
