import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';

/// Handles [ClearItemsEvent] — cancel all uploads and drop all items.
class ClearItemsUseCase extends BlocUseCase<MediaBloc, ClearItemsEvent> {
  @override
  Future<void> execute(ClearItemsEvent event) async {
    if (bloc.state.items.isEmpty) return;

    final ids = bloc.state.items.map((i) => i.id).toList();
    for (final id in ids) {
      bloc.cancelActiveUpload(id);
    }

    emitUpdate(
      newState: bloc.state.copyWith(items: const [], uploads: const {}),
      groupsToRebuild: {MediaGroups.any, ...ids.map(MediaGroups.item)},
    );
  }
}
