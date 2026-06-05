import 'package:juice/juice.dart';

import '../location_bloc.dart';
import '../location_events.dart';
import '../location_state.dart';

/// Handles [StartTrackingEvent] — subscribe to the position stream.
class StartTrackingUseCase
    extends BlocUseCase<LocationBloc, StartTrackingEvent> {
  @override
  Future<void> execute(StartTrackingEvent event) async {
    if (bloc.state.tracking) return;
    bloc.startTracking();
    emitUpdate(
      newState: bloc.state.copyWith(tracking: true, clearError: true),
      groupsToRebuild: {LocationGroups.tracking},
    );
  }
}
