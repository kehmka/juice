import 'package:juice/juice.dart';

import '../analytics_bloc.dart';
import '../analytics_events.dart';
import '../analytics_state.dart';

/// Handles [SetUserEvent] — record the user id in state always; forward identity
/// to the sinks only with consent.
class SetUserUseCase extends BlocUseCase<AnalyticsBloc, SetUserEvent> {
  @override
  Future<void> execute(SetUserEvent event) async {
    if (bloc.state.enabled) {
      await bloc.fanOut((s) => s.setUser(event.userId, event.traits));
    }
    emitUpdate(
      newState: bloc.state.copyWith(userId: event.userId),
      groupsToRebuild: {AnalyticsGroups.status},
    );
  }
}
