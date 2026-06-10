import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';

/// Handles [AddLocalItemsEvent] — append local-file items created outside
/// `pick()` (e.g. rebuilt from persisted paths after a restart). They carry no
/// upload state, so `upload(id)` / `uploadAll()` treat them like fresh picks.
///
/// Fails loud on a remote-origin item (`uri` set) or an item with no content
/// (`path`/`bytes` both null) — silently accepting either would corrupt the
/// gallery's invariants.
class AddLocalItemsUseCase extends BlocUseCase<MediaBloc, AddLocalItemsEvent> {
  @override
  Future<void> execute(AddLocalItemsEvent event) async {
    if (event.items.isEmpty) return;

    for (final item in event.items) {
      if (item.isRemote) {
        throw StateError(
            'AddLocalItemsEvent got remote-origin item "${item.id}" — '
            'use addRemoteItems for hosted items');
      }
      if (item.path == null && item.bytes == null) {
        throw StateError(
            'AddLocalItemsEvent item "${item.id}" has no path or bytes');
      }
    }

    emitUpdate(
      newState: bloc.state
          .copyWith(items: [...bloc.state.items, ...event.items]),
      groupsToRebuild: {
        MediaGroups.any,
        ...event.items.map((i) => MediaGroups.item(i.id)),
      },
    );
  }
}
