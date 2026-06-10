import 'package:juice/juice.dart';

import '../observability_bloc.dart';
import '../observability_events.dart';
import '../observability_state.dart';

/// Handles [RecordErrorEvent] — report the error (with the breadcrumbs that
/// existed at error time) to the reporters, unless capture is disabled.
///
/// Registered `sequential`, so the `errorCount` read-modify-write is race-free.
class RecordErrorUseCase extends BlocUseCase<ObservabilityBloc, RecordErrorEvent> {
  @override
  Future<void> execute(RecordErrorEvent event) async {
    if (!bloc.state.enabled) return;

    await bloc.fanOut((r) => r.recordError(
          event.error,
          event.stack,
          fatal: event.fatal,
          breadcrumbs: bloc.state.breadcrumbs,
        ));

    emitUpdate(
      newState: bloc.state.copyWith(
        errorCount: bloc.state.errorCount + 1,
        lastError: event.error.toString(),
      ),
      groupsToRebuild: {ObservabilityGroups.status},
    );
  }
}
