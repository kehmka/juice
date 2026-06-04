import 'package:juice/juice.dart';

import '../notifications_bloc.dart';
import '../notifications_events.dart';

/// Handles [InitializeNotificationsEvent] — configure the service, initialize
/// the platform, and start listening for taps.
class InitializeNotificationsUseCase
    extends BlocUseCase<NotificationsBloc, InitializeNotificationsEvent> {
  @override
  Future<void> execute(InitializeNotificationsEvent event) async {
    bloc.configure(event.config);
    await bloc.service.initialize();
    bloc.startListeningForTaps();
  }
}
