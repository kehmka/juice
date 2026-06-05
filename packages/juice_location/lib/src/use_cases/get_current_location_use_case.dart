import 'package:juice/juice.dart';

import '../location_bloc.dart';
import '../location_events.dart';
import '../location_state.dart';

/// Handles [GetCurrentLocationEvent] — one-shot read.
class GetCurrentLocationUseCase
    extends BlocUseCase<LocationBloc, GetCurrentLocationEvent> {
  @override
  Future<void> execute(GetCurrentLocationEvent event) async {
    try {
      final position = await bloc.source.current();
      bloc.send(LocationChangedEvent(position));
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(lastError: e.toString()),
        groupsToRebuild: {LocationGroups.error},
        error: e,
      );
    }
  }
}
