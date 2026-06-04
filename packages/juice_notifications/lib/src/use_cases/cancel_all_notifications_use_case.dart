import 'package:juice/juice.dart';

import '../notifications_bloc.dart';
import '../notifications_events.dart';
import '../notifications_state.dart';

/// Handles [CancelAllNotificationsEvent] — cancel everything and clear tracking.
class CancelAllNotificationsUseCase
    extends BlocUseCase<NotificationsBloc, CancelAllNotificationsEvent> {
  @override
  Future<void> execute(CancelAllNotificationsEvent event) async {
    await bloc.service.cancelAll();
    if (bloc.state.scheduled.isNotEmpty) {
      emitUpdate(
        newState: bloc.state.copyWith(scheduled: const []),
        groupsToRebuild: {NotificationsGroups.scheduled},
      );
    }
  }
}
