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
  NotificationsConfig? _config;
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
  NotificationService get service => config.service;

  /// The config [InitializeNotificationsEvent] applied. Throws before that.
  NotificationsConfig get config =>
      _config ??
      (throw StateError('NotificationsBloc is not initialized: send '
          'InitializeNotificationsEvent (or use NotificationsBloc.withConfig) '
          'first'));

  /// Store the config during initialization. One per bloc: a second
  /// `InitializeNotificationsEvent` after the first completed is refused here (the
  /// first provider stays owned and live), loudly, through the use case's
  /// error path.
  void configure(NotificationsConfig config) {
    if (_config != null) {
      throw StateError(
          'NotificationsBloc is already initialized; it owns one config for its life');
    }
    _config = config;
  }

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

  /// Forward service taps as events. The bloc owns the binding: a second
  /// start replaces the first, and close cancels it before the use cases
  /// close. A stream error goes to the bloc's error handler; the binding
  /// keeps listening, as the old subscription did.
  void startListeningForTaps() {
    bindStream<NotificationTap>(
      service.taps,
      (tap) => send(NotificationTappedEvent(tap)),
      key: _tapsKey,
      cancelOnError: false,
    );
  }

  static const _tapsKey = 'taps';

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

  // Memoized like the core's close(): a second caller awaits the first
  // teardown, so the provider is disposed once. `super.close()` is invoked
  // here (the core requires it) and awaited inside.
  @override
  Future<void> close() => _closeOnce ??= _close(super.close());
  Future<void>? _closeOnce;

  Future<void> _close(Future<void> closing) async {
    // The bloc closes first: its taps binding is cancelled before the
    // service it listens to is disposed. An uninitialized bloc has no
    // service.
    await closing;
    final config = _config;
    if (config == null) return;
    // A service operation still in flight (a schedule, a cancel) finishes
    // before the service it runs on is disposed.
    await _serviceOperationTail;
    try {
      await config.service.dispose();
    } catch (error, stackTrace) {
      JuiceLoggerConfig.logger.logError(
          'NotificationService dispose failed', error, stackTrace,
          context: {'type': 'bloc_error', 'bloc': 'NotificationsBloc'});
    }
  }
}
