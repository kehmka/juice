import 'package:juice/juice.dart';

import '../location_bloc.dart';
import '../location_events.dart';
import '../location_state.dart';

/// Handles [TrackingEndedEvent] — the position stream ended or errored:
/// tracking is off, and the error (if any) is in the state.
class TrackingEndedUseCase
    extends BlocUseCase<LocationBloc, TrackingEndedEvent> {
  @override
  Future<void> execute(TrackingEndedEvent event) async {
    if (!bloc.state.tracking) return;
    emitUpdate(
      newState: bloc.state.copyWith(tracking: false, lastError: event.error),
      groupsToRebuild: {
        LocationGroups.tracking,
        if (event.error != null) LocationGroups.error,
      },
    );
  }
}
