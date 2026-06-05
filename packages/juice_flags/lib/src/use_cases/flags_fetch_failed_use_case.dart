import 'package:juice/juice.dart';

import '../flags_bloc.dart';
import '../flags_events.dart';
import '../flags_state.dart';

/// Handles [FlagsFetchFailedEvent] — a live-stream error. Surfaces it loudly;
/// resolved values are left intact so reads stay safe.
class FlagsFetchFailedUseCase
    extends BlocUseCase<FlagsBloc, FlagsFetchFailedEvent> {
  @override
  Future<void> execute(FlagsFetchFailedEvent event) async {
    emitFailure(
      newState: bloc.state.copyWith(loading: false, error: event.error.toString()),
      groupsToRebuild: {FlagsGroups.status},
      error: event.error,
    );
  }
}
