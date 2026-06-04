import 'package:juice/juice.dart';

import '../notifications_bloc.dart';
import '../notifications_events.dart';
import '../notifications_state.dart';

/// Handles [NotificationTappedEvent] — record the tap for app routing.
class NotificationTappedUseCase
    extends BlocUseCase<NotificationsBloc, NotificationTappedEvent> {
  @override
  Future<void> execute(NotificationTappedEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(lastTap: event.tap),
      groupsToRebuild: {NotificationsGroups.tap},
    );
  }
}
