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
  Future<void> _serviceOperationTail = Future<void>.value();

  NotificationsBloc()
      : super(
          NotificationsState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeNotificationsEvent,
                  useCaseGenerator: () => InitializeNotificationsUseCase(),
                  concurrency: EventConcurrency.droppable,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ShowNotificationEvent,
                  useCaseGenerator: () => ShowNotificationUseCase(),
                  // Service mutations share a cross-event FIFO below. They
                  // enter it concurrently to preserve global send order.
                  concurrency: EventConcurrency.concurrent,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ScheduleNotificationEvent,
                  useCaseGenerator: () => ScheduleNotificationUseCase(),
                  concurrency: EventConcurrency.concurrent,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CancelNotificationEvent,
                  useCaseGenerator: () => CancelNotificationUseCase(),
                  concurrency: EventConcurrency.concurrent,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CancelAllNotificationsEvent,
                  useCaseGenerator: () => CancelAllNotificationsUseCase(),
                  concurrency: EventConcurrency.concurrent,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: NotificationTappedEvent,
                  useCaseGenerator: () => NotificationTappedUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SetPermissionStatusEvent,
                  useCaseGenerator: () => SetPermissionStatusUseCase(),
                  concurrency: EventConcurrency.sequential,
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

  /// Run one service mutation at a time across every notification event type.
  ///
  /// Scheduling and cancellation use different runtime event types but mutate
  /// the same platform service and tracked list. Enqueuing before the first
  /// await preserves their global send order.
  Future<void> runServiceOperation(Future<void> Function() operation) async {
    final previous = _serviceOperationTail;
    final done = Completer<void>();
    _serviceOperationTail = done.future;

    try {
      await previous;
      await operation();
    } finally {
      done.complete();
    }
  }

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
