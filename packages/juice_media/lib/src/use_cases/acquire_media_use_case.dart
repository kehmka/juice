import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';

/// Handles [AcquireMediaEvent] — pick/capture, append the results.
class AcquireMediaUseCase extends BlocUseCase<MediaBloc, AcquireMediaEvent> {
  @override
  Future<void> execute(AcquireMediaEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(picking: true, lastError: null),
      groupsToRebuild: {MediaGroups.picking},
    );

    try {
      final picked = await bloc.source.pick(event.request);
      final items = [...bloc.state.items, ...picked];
      emitUpdate(
        newState: bloc.state.copyWith(items: items, picking: false),
        groupsToRebuild: {
          MediaGroups.any,
          MediaGroups.picking,
          ...picked.map((i) => MediaGroups.item(i.id)),
        },
      );
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(picking: false, lastError: e.toString()),
        groupsToRebuild: {MediaGroups.picking, MediaGroups.error},
        error: e,
      );
    }
  }
}
