import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../notification_service.dart';

/// Default [NotificationService] backed by `flutter_local_notifications`
/// 20–22 (the named-parameter API that arrived in 20.0.0).
///
/// Deliberately logic-light: it maps [JuiceNotification] to the plugin and
/// forwards taps. All behavior lives in `NotificationsBloc`, tested with a fake
/// service — this adapter is verified by inspection and a one-time on-device run.
///
/// Scheduling uses `zonedSchedule`, so the app must call
/// `tz.initializeTimeZones()` (from the `timezone` package) once at startup.
class LocalNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<NotificationTap>.broadcast();

  /// Android channel id / name used for posted notifications.
  final String channelId;
  final String channelName;

  LocalNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    this.channelId = 'juice_notifications',
    this.channelName = 'Notifications',
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  NotificationDetails get _details => NotificationDetails(
        android: AndroidNotificationDetails(channelId, channelName),
        iOS: const DarwinNotificationDetails(),
      );

  @override
  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        _taps.add(NotificationTap(
          id: response.id ?? -1,
          payload: response.payload,
        ));
      },
    );
  }

  @override
  Future<void> show(JuiceNotification n) => _plugin.show(
        id: n.id,
        title: n.title,
        body: n.body,
        notificationDetails: _details,
        payload: n.payload,
      );

  @override
  Future<void> schedule(JuiceNotification n, DateTime when) =>
      _plugin.zonedSchedule(
        id: n.id,
        title: n.title,
        body: n.body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: n.payload,
      );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Stream<NotificationTap> get taps => _taps.stream;

  @override
  Future<void> dispose() async {
    await _taps.close();
  }
}
