import 'package:juice/juice.dart';

import 'notification_service.dart';
import 'notifications_config.dart';

/// Base class for notification events.
abstract class NotificationsEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Configure the service, start listening for taps.
class InitializeNotificationsEvent extends NotificationsEvent {
  final NotificationsConfig config;
  InitializeNotificationsEvent({required this.config});
}

/// Post a notification now.
class ShowNotificationEvent extends NotificationsEvent {
  final JuiceNotification notification;
  ShowNotificationEvent(this.notification);
}

/// Post a notification at [when].
class ScheduleNotificationEvent extends NotificationsEvent {
  final JuiceNotification notification;
  final DateTime when;
  ScheduleNotificationEvent(this.notification, this.when);
}

/// Cancel one notification by id.
class CancelNotificationEvent extends NotificationsEvent {
  final int id;
  CancelNotificationEvent(this.id);
}

/// Cancel all notifications.
class CancelAllNotificationsEvent extends NotificationsEvent {}

/// Internal: a notification was tapped (from the service stream).
class NotificationTappedEvent extends NotificationsEvent {
  final NotificationTap tap;
  NotificationTappedEvent(this.tap);
}

/// Set whether the app may post notifications (wire from `juice_permissions`).
class SetPermissionStatusEvent extends NotificationsEvent {
  final bool granted;
  SetPermissionStatusEvent(this.granted);
}
