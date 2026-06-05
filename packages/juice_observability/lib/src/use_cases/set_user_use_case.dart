import 'package:juice/juice.dart';

import '../observability_bloc.dart';
import '../observability_events.dart';
import '../observability_state.dart';

/// Handles [SetUserEvent] — identify the current user across reporters.
class SetUserUseCase extends BlocUseCase<ObservabilityBloc, SetUserEvent> {
  @override
  Future<void> execute(SetUserEvent event) async {
    await bloc.fanOut((r) => r.setUser(event.userId));
    emitUpdate(
      newState: bloc.state.copyWith(userId: event.userId),
      groupsToRebuild: {ObservabilityGroups.status},
    );
  }
}
