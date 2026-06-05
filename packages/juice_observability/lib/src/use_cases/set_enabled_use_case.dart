import 'package:juice/juice.dart';

import '../observability_bloc.dart';
import '../observability_events.dart';
import '../observability_state.dart';

/// Handles [SetEnabledEvent] — enable or disable capture/reporting.
class SetEnabledUseCase extends BlocUseCase<ObservabilityBloc, SetEnabledEvent> {
  @override
  Future<void> execute(SetEnabledEvent event) async {
    if (event.enabled == bloc.state.enabled) return;
    emitUpdate(
      newState: bloc.state.copyWith(enabled: event.enabled),
      groupsToRebuild: {ObservabilityGroups.status},
    );
  }
}
