import 'package:juice/juice.dart';

import '../notifications_bloc.dart';
import '../notifications_events.dart';

/// Handles [ShowNotificationEvent] — post immediately (side-effect; immediate
/// notifications are not tracked in `scheduled`).
class ShowNotificationUseCase
    extends BlocUseCase<NotificationsBloc, ShowNotificationEvent> {
  @override
  Future<void> execute(ShowNotificationEvent event) async {
    await bloc.service.show(event.notification);
  }
}
