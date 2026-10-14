import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_notifications/juice_notifications.dart';

/// Pure-Dart fake — drives the bloc without the plugin.
class FakeNotificationService implements NotificationService {
  late final _taps = StreamController<NotificationTap>.broadcast(
      onListen: () => log.add('listen'), onCancel: () => log.add('cancel'));
  Object? disposeError;

  /// Listen / cancel / dispose, in the order they happened.
  final log = <String>[];
  final List<JuiceNotification> shown = [];
  final List<JuiceNotification> scheduled = [];
  final List<int> cancelled = [];
  final List<String> operations = [];
  Completer<void>? scheduleGate;
  int cancelAllCalls = 0;
  bool disposed = false;

  @override
  Future<void> initialize() async => operations.add('initialize');

  @override
  Future<void> show(JuiceNotification n) async => shown.add(n);

  @override
  Future<void> schedule(JuiceNotification n, DateTime when) async {
    operations.add('schedule:${n.id}:start');
    await scheduleGate?.future;
    scheduled.add(n);
    operations.add('schedule:${n.id}:end');
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async {
    operations.add('cancelAll');
    cancelAllCalls++;
    scheduled.clear();
  }

  @override
  Stream<NotificationTap> get taps => _taps.stream;

  @override
  Future<void> dispose() async {
    log.add('dispose');
    disposed = true;
    if (disposeError != null) throw disposeError!;
    await _taps.close();
  }

  /// Simulate a tap.
  void emitTap(NotificationTap tap) => _taps.add(tap);

  /// Break the tap stream.
  void fail(Object error) => _taps.addError(error);
}

class _CaptureLogger implements JuiceLogger {
  final errors = <String>[];
  @override
  void record(JuiceTelemetry e) {
    if (e.isError) errors.add('${e.message}: ${e.error}');
  }

  @override
  void log(String m,
      {Level level = Level.info, Map<String, dynamic>? context}) {}
  @override
  void logError(String m, Object e, StackTrace s,
          {Map<String, dynamic>? context}) =>
      errors.add('$m: $e');
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

    test('service mutations preserve send order across event types', () async {
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();

      svc.scheduleGate = Completer<void>();
      final first = bloc.send(
        ScheduleNotificationEvent(notif(1), DateTime(2030)),
      );
      await settle();
      final second = bloc.send(
        ScheduleNotificationEvent(notif(2), DateTime(2030)),
      );
      final cancelAll = bloc.send(CancelAllNotificationsEvent());
      await settle();

      expect(svc.operations, ['initialize', 'schedule:1:start']);
      svc.scheduleGate!.complete();
      await Future.wait([first, second, cancelAll]);

      expect(svc.operations, [
        'initialize',
        'schedule:1:start',
        'schedule:1:end',
        'schedule:2:start',
        'schedule:2:end',
        'cancelAll',
      ]);
      expect(svc.scheduled, isEmpty);
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

  group('NotificationsBloc review pins (2.0.0)', () {
    test('close cancels the taps binding before disposing the service',
        () async {
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();
      await bloc.close();
      expect(svc.log, ['listen', 'cancel', 'dispose']);
    });

    test('a second start replaces the binding instead of adding one', () async {
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();
      bloc.startListeningForTaps();
      await settle();
      expect(svc.log, ['listen', 'cancel', 'listen']);
      await bloc.close();
    });

    test(
        'a taps stream error is logged as a bloc error; the binding keeps '
        'listening', () async {
      final saved = JuiceLoggerConfig.logger;
      final log = _CaptureLogger();
      JuiceLoggerConfig.configureLogger(log);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();
      svc.fail(StateError('channel gone'));
      await settle();
      // Two entries by design: the binding's own `stream_binding/error`
      // (it names the key) and the `bloc_error` from the bloc's onError.
      expect(log.errors, hasLength(2));
      expect(log.errors, everyElement(contains('channel gone')));
      expect(svc.log, ['listen'], reason: 'not cancelled on error');
      svc.emitTap(const NotificationTap(id: 7));
      await settle();
      expect(bloc.state.lastTap?.id, 7, reason: 'still listening');
      await bloc.close();
    });

    test('an uninitialized bloc closes cleanly and names its missing config',
        () async {
      final bloc = NotificationsBloc();
      expect(() => bloc.service, throwsStateError);
      await bloc.close();
    });

    test('a service whose dispose throws is logged, not swallowed', () async {
      final saved = JuiceLoggerConfig.logger;
      final log = _CaptureLogger();
      JuiceLoggerConfig.configureLogger(log);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final svc = FakeNotificationService()
        ..disposeError = StateError('channel busy');
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();
      await bloc.close();
      expect(log.errors.single, contains('channel busy'));
    });

    test('a second close() awaits the first: the service is disposed once',
        () async {
      final svc = FakeNotificationService();
      final bloc =
          NotificationsBloc.withConfig(NotificationsConfig(service: svc));
      await settle();
      await Future.wait([bloc.close(), bloc.close()]);
      await bloc.close();
      expect(svc.log.where((e) => e == 'dispose').length, 1);
    });
  });
}
