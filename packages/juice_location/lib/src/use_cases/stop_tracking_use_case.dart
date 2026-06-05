import 'package:juice/juice.dart';

import '../location_bloc.dart';
import '../location_events.dart';
import '../location_state.dart';

/// Handles [StopTrackingEvent] — cancel the position subscription.
class StopTrackingUseCase
    extends BlocUseCase<LocationBloc, StopTrackingEvent> {
  @override
  Future<void> execute(StopTrackingEvent event) async {
    if (!bloc.state.tracking) return;
    bloc.stopTracking();
    emitUpdate(
      newState: bloc.state.copyWith(tracking: false),
      groupsToRebuild: {LocationGroups.tracking},
    );
  }
}
