import 'package:juice/juice.dart';

import '../flags_bloc.dart';
import '../flags_events.dart';
import '../flags_state.dart';

/// Handles [RefreshFlagsEvent] — pull from the source and emit only the flags
/// whose resolved value actually changed.
///
/// On failure the error is surfaced loudly in `state.error`, but the resolved
/// values are left intact so reads keep falling back to last-known/defaults.
class RefreshFlagsUseCase extends BlocUseCase<FlagsBloc, RefreshFlagsEvent> {
  @override
  Future<void> execute(RefreshFlagsEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(loading: true),
      groupsToRebuild: {FlagsGroups.status},
    );

    try {
      final values = await bloc.source.fetch();
      final old = bloc.state.values;
      bloc.applyFetched(values);
      final resolved = bloc.resolve();
      final changed = bloc.changedKeys(old, resolved);

      emitUpdate(
        newState: bloc.state.copyWith(
          values: resolved,
          loading: false,
          fetched: true,
          error: null,
        ),
        groupsToRebuild: {
          FlagsGroups.status,
          FlagsGroups.any,
          ...changed.map(FlagsGroups.flag),
        },
      );
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(loading: false, error: e.toString()),
        groupsToRebuild: {FlagsGroups.status},
        error: e,
      );
    }
  }
}
