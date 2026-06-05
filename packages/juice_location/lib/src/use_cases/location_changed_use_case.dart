import 'package:juice/juice.dart';

import '../location_bloc.dart';
import '../location_events.dart';
import '../location_state.dart';

/// Handles [LocationChangedEvent] — record the new position.
class LocationChangedUseCase
    extends BlocUseCase<LocationBloc, LocationChangedEvent> {
  @override
  Future<void> execute(LocationChangedEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(current: event.position, clearError: true),
      groupsToRebuild: {LocationGroups.position},
    );
  }
}
