import 'package:juice/juice.dart';

import '../notifications_bloc.dart';
import '../notifications_events.dart';
import '../notifications_state.dart';

/// Handles [CancelNotificationEvent] — cancel by id and untrack it.
class CancelNotificationUseCase
    extends BlocUseCase<NotificationsBloc, CancelNotificationEvent> {
  @override
  Future<void> execute(CancelNotificationEvent event) async {
    await bloc.service.cancel(event.id);

    final next =
        bloc.state.scheduled.where((n) => n.id != event.id).toList();
    if (next.length != bloc.state.scheduled.length) {
      emitUpdate(
        newState: bloc.state.copyWith(scheduled: next),
        groupsToRebuild: {NotificationsGroups.scheduled},
      );
    }
  }
}
