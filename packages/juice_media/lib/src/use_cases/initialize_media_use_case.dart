import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';

/// Handles [InitializeMediaEvent] — apply config and seed any remote items.
class InitializeMediaUseCase extends BlocUseCase<MediaBloc, InitializeMediaEvent> {
  @override
  Future<void> execute(InitializeMediaEvent event) async {
    bloc.configure(event.config);
    if (event.config.initialItems.isNotEmpty) {
      bloc.send(AddRemoteItemsEvent(event.config.initialItems));
    }
  }
}
