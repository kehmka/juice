import 'package:juice/juice.dart';

import '../lifecycle_bloc.dart';
import '../lifecycle_events.dart';
import '../lifecycle_state.dart';

/// Handles [LifecycleChangedEvent] — emit when the phase actually changes,
/// tracking the previous phase.
class LifecycleChangedUseCase
    extends BlocUseCase<LifecycleBloc, LifecycleChangedEvent> {
  @override
  Future<void> execute(LifecycleChangedEvent event) async {
    if (event.lifecycle == bloc.state.lifecycle) return; // no-op

    emitUpdate(
      newState: bloc.state.copyWith(
        lifecycle: event.lifecycle,
        previous: bloc.state.lifecycle,
        lastChangedAt: DateTime.now(),
      ),
      groupsToRebuild: {LifecycleGroups.state},
    );
  }
}
