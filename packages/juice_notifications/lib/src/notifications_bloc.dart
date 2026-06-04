import 'package:juice/juice.dart';

import 'notification_service.dart';
import 'notifications_config.dart';
import 'notifications_events.dart';
import 'notifications_state.dart';
import 'use_cases/cancel_all_notifications_use_case.dart';
import 'use_cases/cancel_notification_use_case.dart';
import 'use_cases/initialize_notifications_use_case.dart';
import 'use_cases/notification_tapped_use_case.dart';
import 'use_cases/schedule_notification_use_case.dart';
import 'use_cases/set_permission_status_use_case.dart';
import 'use_cases/show_notification_use_case.dart';

/// Bloc that owns local notification delivery and tap routing.
///
/// Delivers through a [NotificationService] seam (default
/// `LocalNotificationService`), so it is testable without a plugin. Permission
/// status is set externally via [setPermissionStatus] — typically wired from
/// `juice_permissions` with a `PermissionBinding`.
///
/// ```dart
/// final notifications = NotificationsBloc.withConfig(NotificationsConfig());
/// notifications.show(JuiceNotification(id: 1, title: 'Hi', body: 'There'));
/// ```
class NotificationsBloc extends JuiceBloc<NotificationsState> {
  late NotificationsConfig _config;
  StreamSubscription<NotificationTap>? _tapSubscription;

  NotificationsBloc()
      : super(
          NotificationsState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeNotificationsEvent,
                  useCaseGenerator: () => InitializeNotificationsUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ShowNotificationEvent,
                  useCaseGenerator: () => ShowNotificationUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ScheduleNotificationEvent,
                  useCaseGenerator: () => ScheduleNotificationUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CancelNotificationEvent,
                  useCaseGenerator: () => CancelNotificationUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CancelAllNotificationsEvent,
                  useCaseGenerator: () => CancelAllNotificationsUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: NotificationTappedEvent,
                  useCaseGenerator: () => NotificationTappedUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SetPermissionStatusEvent,
                  useCaseGenerator: () => SetPermissionStatusUseCase(),
                ),
          ],
        );

  /// Create and initialize in one step.
  factory NotificationsBloc.withConfig(NotificationsConfig config) {
    final bloc = NotificationsBloc();
    bloc.send(InitializeNotificationsEvent(config: config));
    return bloc;
  }

  /// The active service. Valid after initialization.
  NotificationService get service => _config.service;

  /// Store config during initialization.
  void configure(NotificationsConfig config) => _config = config;

  /// Forward service taps as events.
  void startListeningForTaps() {
    _tapSubscription = service.taps.listen((tap) {
      if (!isClosed) send(NotificationTappedEvent(tap));
    });
  }

  // === Convenience ===

  /// Post a notification now.
  void show(JuiceNotification notification) =>
      send(ShowNotificationEvent(notification));

  /// Post a notification at [when].
  void schedule(JuiceNotification notification, DateTime when) =>
      send(ScheduleNotificationEvent(notification, when));

  /// Cancel one by id.
  void cancel(int id) => send(CancelNotificationEvent(id));

  /// Cancel everything.
  void cancelAll() => send(CancelAllNotificationsEvent());

  /// Set whether posting is allowed (wire from `juice_permissions`).
  void setPermissionStatus(bool granted) =>
      send(SetPermissionStatusEvent(granted));

  @override
  Future<void> close() async {
    await _tapSubscription?.cancel();
    try {
      await _config.service.dispose();
    } catch (_) {
      // Service may never have been configured; ignore.
    }
    await super.close();
  }
}
