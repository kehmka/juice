import 'package:juice/juice.dart';

import '../realtime_bloc.dart';
import '../realtime_events.dart';

/// Handles [InitializeRealtimeEvent] — apply config; auto-connect if configured.
class InitializeRealtimeUseCase
    extends BlocUseCase<RealtimeBloc, InitializeRealtimeEvent> {
  @override
  Future<void> execute(InitializeRealtimeEvent event) async {
    bloc.configure(event.config);
    if (event.config.autoConnect) {
      bloc.send(ConnectEvent());
    }
  }
}
