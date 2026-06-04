import 'package:juice/juice.dart';

import '../notifications_bloc.dart';
import '../notifications_events.dart';
import '../notifications_state.dart';

/// Handles [ScheduleNotificationEvent] — schedule for later and track it.
class ScheduleNotificationUseCase
    extends BlocUseCase<NotificationsBloc, ScheduleNotificationEvent> {
  @override
  Future<void> execute(ScheduleNotificationEvent event) async {
    await bloc.service.schedule(event.notification, event.when);

    final next = [
      ...bloc.state.scheduled.where((n) => n.id != event.notification.id),
      event.notification,
    ];
    emitUpdate(
      newState: bloc.state.copyWith(scheduled: next),
      groupsToRebuild: {NotificationsGroups.scheduled},
    );
  }
}
