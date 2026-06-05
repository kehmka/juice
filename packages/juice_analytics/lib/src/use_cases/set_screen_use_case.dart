import 'package:juice/juice.dart';

import '../analytics_bloc.dart';
import '../analytics_events.dart';
import '../analytics_state.dart';

/// Handles [SetScreenEvent] — record a screen view (dropped when consent is off).
class SetScreenUseCase extends BlocUseCase<AnalyticsBloc, SetScreenEvent> {
  @override
  Future<void> execute(SetScreenEvent event) async {
    if (!bloc.state.enabled) return;

    await bloc.fanOut((s) => s.setScreen(event.name));
    emitUpdate(
      newState: bloc.state.copyWith(screenName: event.name),
      groupsToRebuild: {AnalyticsGroups.screen, AnalyticsGroups.status},
    );
  }
}
