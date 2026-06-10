import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';

/// Handles [AcquireMediaEvent] — pick/capture, append the results.
class AcquireMediaUseCase extends BlocUseCase<MediaBloc, AcquireMediaEvent> {
  @override
  Future<void> execute(AcquireMediaEvent event) async {
    // No entry guard: the builder is `droppable`, so a pick fired while one is
    // in flight never reaches this use case.
    emitUpdate(
      newState: bloc.state.copyWith(picking: true, lastError: null),
      groupsToRebuild: {MediaGroups.picking},
    );

    try {
      var picked = await bloc.source.pick(event.request);
      // Stamp the request's session tag so contexts can partition items.
      final session = event.request.session;
      if (session != null) {
        picked = [for (final i in picked) i.withSession(session)];
      }
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
