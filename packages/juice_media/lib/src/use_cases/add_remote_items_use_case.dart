import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';
import '../upload_state.dart';

/// Handles [AddRemoteItemsEvent] — append remote-origin items, each seeded as a
/// `completed` upload so the gallery treats them uniformly (rendered, counted in
/// `allUploaded`, skipped by `uploadAll`).
class AddRemoteItemsUseCase extends BlocUseCase<MediaBloc, AddRemoteItemsEvent> {
  @override
  Future<void> execute(AddRemoteItemsEvent event) async {
    if (event.items.isEmpty) return;

    final items = [...bloc.state.items, ...event.items];
    final uploads = {...bloc.state.uploads};
    for (final item in event.items) {
      uploads[item.id] = UploadState.remote(item.id, item.uri);
    }

    emitUpdate(
      newState: bloc.state.copyWith(items: items, uploads: uploads),
      groupsToRebuild: {
        MediaGroups.any,
        ...event.items.map((i) => MediaGroups.item(i.id)),
      },
    );
  }
}
