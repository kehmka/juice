import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_notifications/juice_notifications.dart';

/// Pure-Dart fake — drives the bloc without the plugin.
class FakeNotificationService implements NotificationService {
  final _taps = StreamController<NotificationTap>.broadcast();
  final List<JuiceNotification> shown = [];
  final List<JuiceNotification> scheduled = [];
  final List<int> cancelled = [];
  int cancelAllCalls = 0;
  bool disposed = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show(JuiceNotification n) async => shown.add(n);

  @override
  Future<void> schedule(JuiceNotification n, DateTime when) async =>
      scheduled.add(n);

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => cancelAllCalls++;

  @override
  Stream<NotificationTap> get taps => _taps.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _taps.close();
  }

  /// Simulate a tap.
  void emitTap(NotificationTap tap) => _taps.add(tap);
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  JuiceNotification notif(int id, {String? payload}) =>
      JuiceNotification(id: id, title: 'T$id', body: 'B$id', payload: payload);

  group('NotificationsState model', () {
    test('defaults', () {
      const s = NotificationsState();
      expect(s.scheduled, isEmpty);
      expect(s.lastTap, isNull);
      expect(s.permissionGranted, isFalse);
    });
  });

  group('NotificationsBloc', () {
    test('show posts immediately, not tracked in scheduled', () async {
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();

      bloc.show(notif(1));
      await settle();

      expect(svc.shown.single.id, 1);
      expect(bloc.state.scheduled, isEmpty);
      await bloc.close();
    });

    test('schedule tracks the notification', () async {
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();

      bloc.schedule(notif(7), DateTime(2030));
      await settle();

      expect(svc.scheduled.single.id, 7);
      expect(bloc.state.scheduled.single.id, 7);
      await bloc.close();
    });

    test('cancel removes from scheduled', () async {
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();

      bloc.schedule(notif(1), DateTime(2030));
      bloc.schedule(notif(2), DateTime(2030));
      await settle();
      expect(bloc.state.scheduled.length, 2);

      bloc.cancel(1);
      await settle();

      expect(svc.cancelled, [1]);
      expect(bloc.state.scheduled.single.id, 2);
      await bloc.close();
    });

    test('cancelAll clears tracking', () async {
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();

      bloc.schedule(notif(1), DateTime(2030));
      await settle();

      bloc.cancelAll();
      await settle();

      expect(svc.cancelAllCalls, 1);
      expect(bloc.state.scheduled, isEmpty);
      await bloc.close();
    });

    test('a tap is surfaced as lastTap', () async {
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();

      svc.emitTap(const NotificationTap(id: 42, payload: '/deep/link'));
      await settle();

      expect(bloc.state.lastTap?.id, 42);
      expect(bloc.state.lastTap?.payload, '/deep/link');
      await bloc.close();
    });

    test('setPermissionStatus updates state (deduped)', () async {
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();
      expect(bloc.state.permissionGranted, isFalse);

      bloc.setPermissionStatus(true);
      await settle();
      expect(bloc.state.permissionGranted, isTrue);
      await bloc.close();
    });

    test('close disposes the service', () async {
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();

      await bloc.close();
      expect(svc.disposed, isTrue);
    });
  });
}
