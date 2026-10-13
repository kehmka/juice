import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// `JuiceBloc.bindStream` / `unbind` / `StreamBinding` (2.0.0): the bloc
/// owns every stream it listens to. Every path is pinned here: delivery,
/// keyed replacement, unbind, cancel, done, close-cancels-all, no delivery
/// while closing, refusal after close, the error contract (bloc handler,
/// custom handler, cancelOnError, a throwing onData), telemetry, and the
/// end-to-end shape a use case uses (bind in one use case, items become
/// events, a later use case unbinds).

class _S extends BlocState {
  const _S(this.items, {this.stopped = false});
  final List<int> items;
  final bool stopped;
}

class _Start extends EventBase {
  _Start(this.source);
  final Stream<int> source;
}

class _Stop extends EventBase {}

class _Got extends EventBase {
  _Got(this.v);
  final int v;
}

class _StartUC extends BlocUseCase<_B, _Start> {
  @override
  Future<void> execute(_Start e) async {
    bloc.bindStream<int>(e.source, (v) => bloc.send(_Got(v)), key: 'source');
  }
}

class _StopUC extends BlocUseCase<_B, _Stop> {
  @override
  Future<void> execute(_Stop e) async {
    final had = bloc.unbind('source');
    emitUpdate(
        newState: _S(bloc.state.items, stopped: had), groupsToRebuild: {'g'});
  }
}

class _GotUC extends BlocUseCase<_B, _Got> {
  @override
  Future<void> execute(_Got e) async => emitUpdate(
      newState: _S([...bloc.state.items, e.v]), groupsToRebuild: {'g'});
}

class _B extends JuiceBloc<_S> {
  _B({JuiceLogger? logger, BlocErrorHandler? errorHandler})
      : super(
          const _S([]),
          [
            () => UseCaseBuilder.typed(() => _StartUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _StopUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _GotUC(),
                concurrency: EventConcurrency.sequential),
          ],
          const [],
          logger,
          errorHandler ?? const BlocErrorHandler(),
        );

  final errors = <Object>[];
  @override
  void onError(Object error, StackTrace stackTrace) {
    errors.add(error);
    super.onError(error, stackTrace);
  }
}

class _Log implements JuiceLogger {
  final entries = <Map<String, dynamic>>[];
  final errors = <String>[];
  @override
  void log(String m,
          {Level level = Level.info, Map<String, dynamic>? context}) =>
      entries.add({'message': m, 'level': level, ...?context});
  @override
  void logError(String m, Object e, StackTrace s,
      {Map<String, dynamic>? context}) {
    errors.add(m);
    entries.add({'message': m, 'error': e, ...?context});
  }

  Iterable<Map<String, dynamic>> bindings(String action) => entries
      .where((e) => e['type'] == 'stream_binding' && e['action'] == action);
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

/// Swallows the default handler's print; the tests assert on [_B.errors].
final _quiet = BlocErrorHandler(onError: (m, {error, stackTrace}) {});

void main() {
  late JuiceLogger savedLogger;
  late Level savedLevel;
  setUp(() {
    savedLogger = JuiceLoggerConfig.logger;
    savedLevel = JuiceLoggerConfig.minLevel;
    JuiceLoggerConfig.minLevel = Level.all;
  });
  tearDown(() {
    JuiceLoggerConfig.configureLogger(savedLogger);
    JuiceLoggerConfig.minLevel = savedLevel;
  });

  group('delivery and lifetime', () {
    test('items reach onData while the bloc is open', () async {
      final b = _B();
      final c = StreamController<int>();
      final got = <int>[];
      final binding = b.bindStream<int>(c.stream, got.add);
      expect(binding.isActive, isTrue);
      expect(binding.key, isNull);
      expect(b.activeBindingCount, 1);
      c
        ..add(1)
        ..add(2);
      await pump();
      expect(got, [1, 2]);
      await c.close();
      await b.close();
    });

    test('done completes and the binding deregisters when the stream ends',
        () async {
      final b = _B();
      final c = StreamController<int>();
      var doneCalled = 0;
      final binding =
          b.bindStream<int>(c.stream, (_) {}, onDone: () => doneCalled++);
      await c.close();
      await binding.done;
      expect(binding.isActive, isFalse);
      expect(doneCalled, 1);
      expect(b.activeBindingCount, 0);
      await b.close();
    });

    test(
        'cancel stops delivery, completes done, is idempotent, and '
        'returns the subscription cancel future', () async {
      final b = _B();
      var cancelled = 0;
      final c = StreamController<int>(onCancel: () async {
        cancelled++;
        await pump();
      });
      final got = <int>[];
      final binding = b.bindStream<int>(c.stream, got.add);
      c.add(1);
      await pump();
      await binding.cancel();
      expect(cancelled, 1, reason: 'the underlying subscription was cancelled');
      await binding.cancel();
      expect(cancelled, 1, reason: 'idempotent');
      expect(binding.isActive, isFalse);
      await binding.done;
      c.add(2);
      await pump();
      expect(got, [1]);
      expect(b.activeBindingCount, 0);
      await c.close();
      await b.close();
    });

    test('several anonymous bindings coexist and cancel independently',
        () async {
      final b = _B();
      final c1 = StreamController<int>();
      final c2 = StreamController<String>();
      final ints = <int>[];
      final strings = <String>[];
      final b1 = b.bindStream<int>(c1.stream, ints.add);
      b.bindStream<String>(c2.stream, strings.add);
      expect(b.activeBindingCount, 2);
      await b1.cancel();
      c1.add(1);
      c2.add('a');
      await pump();
      expect(ints, isEmpty);
      expect(strings, ['a']);
      expect(b.activeBindingCount, 1);
      await c1.close();
      await c2.close();
      await b.close();
    });
  });

  group('keys', () {
    test('a re-bind with the same key replaces the earlier binding', () async {
      final b = _B();
      final old = StreamController<int>();
      final fresh = StreamController<int>();
      final got = <int>[];
      final first = b.bindStream<int>(old.stream, got.add, key: 'k');
      final second = b.bindStream<int>(fresh.stream, got.add, key: 'k');
      expect(first.isActive, isFalse, reason: 'replaced');
      await first.done;
      expect(second.isActive, isTrue);
      expect(second.key, 'k');
      expect(b.activeBindingCount, 1);
      old.add(1);
      fresh.add(2);
      await pump();
      expect(got, [2]);
      await old.close();
      await fresh.close();
      await b.close();
    });

    test('unbind cancels by key and reports whether anything was bound',
        () async {
      final b = _B();
      final c = StreamController<int>();
      final binding = b.bindStream<int>(c.stream, (_) {}, key: 'k');
      expect(b.unbind('k'), isTrue);
      expect(binding.isActive, isFalse);
      expect(b.unbind('k'), isFalse, reason: 'nothing left under the key');
      expect(b.unbind('never'), isFalse);
      await c.close();
      await b.close();
    });

    test('a key whose stream ended is free again', () async {
      final b = _B();
      final c = StreamController<int>();
      final binding = b.bindStream<int>(c.stream, (_) {}, key: 'k');
      await c.close();
      await binding.done;
      expect(b.unbind('k'), isFalse);
      final c2 = StreamController<int>();
      final again = b.bindStream<int>(c2.stream, (_) {}, key: 'k');
      expect(again.isActive, isTrue);
      await c2.close();
      await b.close();
    });

    test('cancelling a replaced binding does not disturb its successor',
        () async {
      final b = _B();
      final c1 = StreamController<int>();
      final c2 = StreamController<int>();
      final first = b.bindStream<int>(c1.stream, (_) {}, key: 'k');
      final second = b.bindStream<int>(c2.stream, (_) {}, key: 'k');
      await first.cancel();
      expect(second.isActive, isTrue);
      expect(b.unbind('k'), isTrue);
      await c1.close();
      await c2.close();
      await b.close();
    });
  });

  group('close', () {
    test('close cancels every binding first and awaits their cancels',
        () async {
      final b = _B();
      final order = <String>[];
      final c = StreamController<int>(onCancel: () async {
        await pump();
        order.add('cancelled');
      });
      final binding = b.bindStream<int>(c.stream, (_) {});
      final closing = b.close().then((_) => order.add('closed'));
      await closing;
      expect(order, ['cancelled', 'closed']);
      expect(binding.isActive, isFalse);
      expect(b.activeBindingCount, 0);
      await c.close();
    });

    test('onData does not run for an item delivered while closing', () async {
      final b = _B();
      final got = <int>[];
      // A subscription whose cancel is slow, so the close is still in
      // progress when the item arrives.
      final c = StreamController<int>(onCancel: () => pump());
      b.bindStream<int>(c.stream, got.add);
      final closing = b.close();
      c.add(1); // delivered on the next microtask, mid-close
      await closing;
      expect(got, isEmpty);
      await c.close();
    });

    test('bindStream on a closed bloc is refused: inert binding, loud log',
        () async {
      final log = _Log();
      final b = _B(logger: log);
      await b.close();
      final c = StreamController<int>();
      final got = <int>[];
      final binding = b.bindStream<int>(c.stream, got.add, key: 'late');
      expect(binding.isActive, isFalse);
      expect(binding.key, 'late');
      await binding.done;
      expect(c.hasListener, isFalse, reason: 'never subscribed');
      expect(b.activeBindingCount, 0);
      final refused = log.bindings('refused').single;
      expect(refused['level'], Level.warning);
      expect(refused['key'], 'late');
      expect(refused['reason'], 'bloc is closed');
      c.add(1);
      await pump();
      expect(got, isEmpty);
      // No listener ever attached, so close() would never complete.
      unawaited(c.close());
    });

    test('the close log carries the number of live bindings', () async {
      final log = _Log();
      final b = _B(logger: log);
      final c = StreamController<int>();
      b.bindStream<int>(c.stream, (_) {});
      await b.close();
      final close = log.entries.firstWhere(
          (e) => e['type'] == 'bloc_lifecycle' && e['action'] == 'close');
      expect(close['streamBindings'], 1);
      await c.close();
    });
  });

  group('errors', () {
    test(
        'a stream error with no onError goes to the bloc error handler, '
        'is logged, and cancels the binding', () async {
      final log = _Log();
      final handled = <Object?>[];
      final b = _B(
          logger: log,
          errorHandler: BlocErrorHandler(
              onError: (m, {error, stackTrace}) => handled.add(error)));
      final c = StreamController<int>();
      final got = <int>[];
      final binding = b.bindStream<int>(c.stream, got.add);
      c.addError(StateError('boom'));
      await pump();
      expect(b.errors.single, isA<StateError>());
      expect(handled.single, isA<StateError>());
      expect(log.bindings('error').single['message'], 'Stream binding error');
      expect(binding.isActive, isFalse, reason: 'cancelOnError defaults true');
      c.add(1);
      await pump();
      expect(got, isEmpty);
      await c.close();
      await b.close();
    });

    test('cancelOnError: false keeps listening after a logged error', () async {
      final b = _B(logger: _Log(), errorHandler: _quiet);
      final c = StreamController<int>();
      final got = <int>[];
      final binding =
          b.bindStream<int>(c.stream, got.add, cancelOnError: false);
      c.addError(StateError('transient'));
      c.add(1);
      await pump();
      expect(b.errors, hasLength(1));
      expect(binding.isActive, isTrue);
      expect(got, [1]);
      await c.close();
      await b.close();
    });

    test(
        'a custom onError receives the error instead of the bloc handler, '
        'and the binding is still cancelled by default', () async {
      final b = _B(logger: _Log());
      final c = StreamController<int>();
      final seen = <Object>[];
      final binding =
          b.bindStream<int>(c.stream, (_) {}, onError: (e, st) => seen.add(e));
      c.addError(StateError('mine'));
      await pump();
      expect(seen.single, isA<StateError>());
      expect(b.errors, isEmpty, reason: 'not routed to the bloc');
      expect(binding.isActive, isFalse);
      await c.close();
      await b.close();
    });

    test('a custom onError with cancelOnError: false keeps the binding',
        () async {
      final b = _B(logger: _Log());
      final c = StreamController<int>();
      final seen = <Object>[];
      final binding = b.bindStream<int>(c.stream, (_) {},
          onError: (e, st) => seen.add(e), cancelOnError: false);
      c.addError(StateError('one'));
      c.addError(StateError('two'));
      await pump();
      expect(seen, hasLength(2));
      expect(binding.isActive, isTrue);
      await c.close();
      await b.close();
    });

    test(
        'an onData that throws is routed to the bloc error handler and the '
        'binding stays active', () async {
      final log = _Log();
      final b = _B(logger: log);
      final c = StreamController<int>();
      final got = <int>[];
      final binding = b.bindStream<int>(c.stream, (v) {
        if (v == 2) throw ArgumentError('bad item');
        got.add(v);
      });
      c
        ..add(1)
        ..add(2)
        ..add(3);
      await pump();
      expect(got, [1, 3]);
      expect(b.errors.single, isA<ArgumentError>());
      final threw = log.bindings('callback_error').single;
      expect(threw['message'], 'Stream binding onData threw');
      expect(threw['callback'], 'onData');
      expect(binding.isActive, isTrue);
      await c.close();
      await b.close();
    });
  });

  group('telemetry', () {
    test(
        'bind and done are chatter: logged at the default level, not '
        'built below it', () async {
      final log = _Log();
      JuiceLoggerConfig.configureLogger(log);
      final b = _B(logger: log);
      final c = StreamController<int>();
      b.bindStream<int>(c.stream, (_) {}, key: 'k');
      await c.close();
      await pump();
      expect(log.bindings('bind').single['key'], 'k');
      expect(log.bindings('done').single['key'], 'k');
      await b.close();

      final quiet = _Log();
      JuiceLoggerConfig.configureLogger(quiet);
      JuiceLoggerConfig.minLevel = Level.warning;
      final b2 = _B(logger: quiet);
      final c2 = StreamController<int>();
      b2.bindStream<int>(c2.stream, (_) {});
      await c2.close();
      await pump();
      expect(quiet.bindings('bind'), isEmpty);
      expect(quiet.bindings('done'), isEmpty);
      await b2.close();
    });
  });

  group('from a use case', () {
    test(
        'bind in one use case, items become events, a later use case '
        'unbinds, close is clean', () async {
      final b = _B(logger: _Log());
      final c = StreamController<int>();
      await b.send(_Start(c.stream));
      expect(b.activeBindingCount, 1);
      c
        ..add(1)
        ..add(2);
      await pump();
      await pump();
      expect(b.state.items, [1, 2]);
      await b.send(_Stop());
      expect(b.state.stopped, isTrue, reason: 'unbind reported a binding');
      expect(b.activeBindingCount, 0);
      c.add(3);
      await pump();
      await pump();
      expect(b.state.items, [1, 2], reason: 'after unbind nothing arrives');
      await b.send(_Stop());
      expect(b.state.stopped, isFalse, reason: 'nothing left to unbind');
      await c.close();
      await b.close();
    });

    test(
        'a binding started by a use case is cancelled by close, and an '
        'item arriving afterwards is not sent', () async {
      final b = _B(logger: _Log());
      final c = StreamController<int>();
      await b.send(_Start(c.stream));
      await b.close();
      expect(b.activeBindingCount, 0);
      c.add(9);
      await pump();
      expect(b.state.items, isEmpty);
      await c.close();
    });
  });
}
