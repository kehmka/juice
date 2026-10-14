import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_location/juice_location.dart';

/// Pure-Dart fake — drives the bloc without a device.
class FakeLocationSource implements LocationSource {
  final _controller = StreamController<GeoPosition>.broadcast();
  GeoPosition? currentValue;
  Object? currentError;
  Completer<GeoPosition>? currentGate;
  int currentCalls = 0;
  bool disposed = false;

  @override
  Future<GeoPosition> current() async {
    currentCalls++;
    if (currentError != null) throw currentError!;
    if (currentGate case final gate?) return gate.future;
    return currentValue!;
  }

  @override
  Stream<GeoPosition> positions() => _controller.stream;

  Object? disposeError;
  int disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposed = true;
    disposeCalls++;
    if (disposeError != null) throw disposeError!;
    await _controller.close();
  }

  void emit(GeoPosition p) => _controller.add(p);
  void fail(Object error) => _controller.addError(error);
  Future<void> end() => _controller.close();
}

class _CaptureLogger implements JuiceLogger {
  @override
  void record(JuiceTelemetry e) {
    if (e.isError) errors.add('${e.message}: ${e.error}');
  }

  final errors = <String>[];
  @override
  void log(String m,
      {Level level = Level.info, Map<String, dynamic>? context}) {}
  @override
  void logError(String m, Object e, StackTrace s,
          {Map<String, dynamic>? context}) =>
      errors.add('$m: $e');
}

GeoPosition pos(double lat, double lng) =>
    GeoPosition(latitude: lat, longitude: lng, timestamp: DateTime(2026));

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('LocationState model', () {
    test('defaults', () {
      const s = LocationState();
      expect(s.current, isNull);
      expect(s.tracking, isFalse);
      expect(s.permissionGranted, isFalse);
    });
  });

  group('LocationBloc', () {
    test('getCurrent reads a one-shot position', () async {
      final src = FakeLocationSource()..currentValue = pos(1, 2);
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      bloc.getCurrent();
      await settle();

      expect(bloc.state.current?.latitude, 1);
      expect(bloc.state.current?.longitude, 2);
      await bloc.close();
    });

    test('getCurrent surfaces an error', () async {
      final src = FakeLocationSource()..currentError = StateError('no fix');
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      bloc.getCurrent();
      await settle();

      expect(bloc.state.lastError, contains('no fix'));
      await bloc.close();
    });

    test('drops a second one-shot read while the first is in flight', () async {
      final src = FakeLocationSource()..currentGate = Completer<GeoPosition>();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      final first = bloc.send(GetCurrentLocationEvent());
      await settle();
      final second = bloc.send(GetCurrentLocationEvent());
      await settle();

      expect(src.currentCalls, 1);
      src.currentGate!.complete(pos(3, 4));
      await Future.wait([first, second]);
      expect(bloc.state.current?.latitude, 3);
      await bloc.close();
    });

    test('startTracking streams positions; stopTracking ends it', () async {
      final src = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      bloc.startTrackingUpdates();
      await settle();
      expect(bloc.state.tracking, isTrue);

      src.emit(pos(10, 20));
      await settle();
      expect(bloc.state.current?.latitude, 10);

      bloc.stopTrackingUpdates();
      await settle();
      expect(bloc.state.tracking, isFalse);

      // No more updates after stop.
      src.emit(pos(99, 99));
      await settle();
      expect(bloc.state.current?.latitude, 10); // unchanged
      await bloc.close();
    });

    test('setPermissionStatus updates state (deduped)', () async {
      final src = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      bloc.setPermissionStatus(true);
      await settle();
      expect(bloc.state.permissionGranted, isTrue);
      await bloc.close();
    });

    test('processes rapid position updates in event order', () async {
      final src = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      final first = bloc.send(LocationChangedEvent(pos(1, 1)));
      final second = bloc.send(LocationChangedEvent(pos(2, 2)));
      final third = bloc.send(LocationChangedEvent(pos(3, 3)));
      await Future.wait([first, second, third]);

      expect(bloc.state.current?.latitude, 3);
      await bloc.close();
    });

    test('close disposes the source', () async {
      final src = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      await bloc.close();
      expect(src.disposed, isTrue);
    });
  });

  group('LocationBloc review pins (2.0.0)', () {
    test('a positions stream error ends tracking, with the error in state',
        () async {
      final src = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();
      bloc.startTrackingUpdates();
      await settle();
      src.fail(StateError('gps lost'));
      await settle();
      expect(bloc.state.tracking, isFalse);
      expect(bloc.state.lastError, contains('gps lost'));
      await bloc.close();
    });

    test('a positions stream that ends on its own ends tracking', () async {
      final src = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();
      bloc.startTrackingUpdates();
      await settle();
      await src.end();
      await settle();
      expect(bloc.state.tracking, isFalse);
      expect(bloc.state.lastError, isNull);
      await bloc.close();
    });

    test('close cancels the tracking binding before disposing the source',
        () async {
      final src = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();
      bloc.startTrackingUpdates();
      await settle();
      await bloc.close();
      expect(src.disposed, isTrue);
      // The source's dispose closes its stream; had the binding still been
      // listening, that onDone would have reached the bloc.
      expect(bloc.state.tracking, isTrue, reason: 'frozen as it was');
    });

    test('an uninitialized bloc closes cleanly and names its missing config',
        () async {
      final bloc = LocationBloc();
      expect(() => bloc.source, throwsStateError);
      await bloc.close();
    });

    test('a source whose dispose throws is logged, not swallowed', () async {
      final saved = JuiceLoggerConfig.logger;
      final log = _CaptureLogger();
      JuiceLoggerConfig.configureLogger(log);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final src = FakeLocationSource()..disposeError = StateError('gps busy');
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();
      await bloc.close();
      expect(log.errors.single, contains('gps busy'));
    });

    test('a second close() awaits the first: the source is disposed once',
        () async {
      final src = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();
      await Future.wait([bloc.close(), bloc.close()]);
      await bloc.close();
      expect(bloc.activeBindingCount, 0);
      expect(src.disposeCalls, 1);
    });

    test(
        'a second initialization after the first is refused; the first '
        'provider stays', () async {
      final saved = JuiceLoggerConfig.logger;
      final log = _CaptureLogger();
      JuiceLoggerConfig.configureLogger(log);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final first = FakeLocationSource();
      final second = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: first));
      await settle();
      await bloc.send(
          InitializeLocationEvent(config: LocationConfig(source: second)));
      await settle();
      // Two entries by the 2.0 contract: the span's `use_case_error` and the
      // `bloc_error`.
      expect(log.errors, hasLength(2));
      expect(log.errors, everyElement(contains('already initialized')));
      expect(bloc.source, same(first));
      await bloc.close();
      expect(first.disposed, isTrue);
      expect(second.disposed, isFalse, reason: 'never owned');
    });
  });
}
