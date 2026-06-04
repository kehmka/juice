/// A notification to post — immediately ([NotificationsBloc.show]) or at a time
/// ([NotificationsBloc.schedule]).
class JuiceNotification {
  /// Stable id (used to cancel/replace).
  final int id;
  final String title;
  final String body;

  /// Opaque payload delivered back on tap (e.g. a route or json).
  final String? payload;

  const JuiceNotification({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  });
}

/// A tapped notification, surfaced for the app to route on.
class NotificationTap {
  final int id;
  final String? payload;
  const NotificationTap({required this.id, this.payload});
}

/// Vendor seam for delivering local notifications.
///
/// `NotificationsBloc` depends on this interface, not on a plugin — testable
/// with a fake. The default implementation is `LocalNotificationService`
/// (backed by `flutter_local_notifications`).
abstract class NotificationService {
  /// Platform initialization (channels, tap handler wiring).
  Future<void> initialize();

  /// Post a notification now.
  Future<void> show(JuiceNotification notification);

  /// Post a notification at [when].
  Future<void> schedule(JuiceNotification notification, DateTime when);

  /// Cancel a pending/shown notification by id.
  Future<void> cancel(int id);

  /// Cancel everything.
  Future<void> cancelAll();

  /// Stream of taps on delivered notifications.
  Stream<NotificationTap> get taps;

  /// Release resources.
  Future<void> dispose();
}
