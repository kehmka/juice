import 'dart:async';

import 'package:juice_notifications/juice_notifications.dart';

/// A no-op [NotificationService] for the demo — records nothing to the OS, so
/// the app runs with no plugin, timezone setup, or device. The bloc's tracking
/// (scheduled list) and tap routing still work end-to-end.
class DemoNotificationService implements NotificationService {
  final _taps = StreamController<NotificationTap>.broadcast();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show(JuiceNotification n) async {}

  @override
  Future<void> schedule(JuiceNotification n, DateTime when) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Stream<NotificationTap> get taps => _taps.stream;

  @override
  Future<void> dispose() async => _taps.close();

  /// Demo affordance: simulate a tap.
  void simulateTap(NotificationTap tap) => _taps.add(tap);
}
