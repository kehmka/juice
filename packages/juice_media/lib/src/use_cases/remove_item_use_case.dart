import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';

/// Handles [RemoveItemEvent] — drop an item and cancel/clear its upload.
class RemoveItemUseCase extends BlocUseCase<MediaBloc, RemoveItemEvent> {
  @override
  Future<void> execute(RemoveItemEvent event) async {
    if (!bloc.state.items.any((i) => i.id == event.id)) return;

    bloc.cancelActiveUpload(event.id); // no-op if not uploading

    final items = bloc.state.items.where((i) => i.id != event.id).toList();
    final uploads = {...bloc.state.uploads}..remove(event.id);

    emitUpdate(
      newState: bloc.state.copyWith(items: items, uploads: uploads),
      groupsToRebuild: {MediaGroups.any, MediaGroups.item(event.id)},
    );
  }
}
