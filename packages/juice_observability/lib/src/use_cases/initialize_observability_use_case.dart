import 'package:juice/juice.dart';

import '../observability_bloc.dart';
import '../observability_events.dart';
import '../observability_state.dart';

/// Handles [InitializeObservabilityEvent] — apply config; install global error
/// handlers if configured.
class InitializeObservabilityUseCase
    extends BlocUseCase<ObservabilityBloc, InitializeObservabilityEvent> {
  @override
  Future<void> execute(InitializeObservabilityEvent event) async {
    bloc.configure(event.config);
    if (event.config.captureUncaught) {
      bloc.installHandlers();
    }
    emitUpdate(
      newState: bloc.state,
      groupsToRebuild: {ObservabilityGroups.status},
    );
  }
}
