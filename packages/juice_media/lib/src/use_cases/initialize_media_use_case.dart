import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';

/// Handles [InitializeMediaEvent] — apply config.
class InitializeMediaUseCase extends BlocUseCase<MediaBloc, InitializeMediaEvent> {
  @override
  Future<void> execute(InitializeMediaEvent event) async {
    bloc.configure(event.config);
  }
}
