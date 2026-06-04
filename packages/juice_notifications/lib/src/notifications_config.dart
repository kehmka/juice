import 'notification_service.dart';
import 'providers/local_notification_service.dart';

/// Configuration for [NotificationsBloc].
class NotificationsConfig {
  /// The delivery backend. Defaults to [LocalNotificationService].
  ///
  /// Pass a fake here in tests to drive notifications without a plugin.
  final NotificationService service;

  NotificationsConfig({NotificationService? service})
      : service = service ?? LocalNotificationService();
}
