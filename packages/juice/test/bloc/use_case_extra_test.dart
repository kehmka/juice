// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

class _S extends BlocState {
  final int n;
  const _S([this.n = 0]);
  _S copyWith({int? n}) => _S(n ?? this.n);
  @override
  String toString() => '_S($n)';
}

class _Entry {
  final String message;
  final Level level;
  final Map<String, dynamic>? context;
  final Object? error;
  _Entry(this.message, this.level, this.context, [this.error]);
}

class _CaptureLogger implements JuiceLogger {
  final entries = <_Entry>[];

  @override
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    entries.add(_Entry(message, level, context));
  }

  @override
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) {
    entries.add(_Entry(message, Level.error, context, error));
  }

  Iterable<_Entry> matching(String prefix) =>
      entries.where((e) => e.message.startsWith(prefix));
}

// ---------------------------------------------------------------------------
// BlocUseCase logging helpers

class _LogEvent extends EventBase {}

class _LoggingUseCase extends BlocUseCase<_LogBloc, _LogEvent> {
  @override
  Future<void> execute(_LogEvent event) async {
    log('hello', level: Level.warning, context: {'extra': 1});
    log('plain');
    logState('after load', context: {'k': 'v'});
    logError(StateError('bad'), StackTrace.current, context: {'where': 'x'});
    logError(ArgumentError('worse'), StackTrace.current);
  }
}

class _LogBloc extends JuiceBloc<_S> {
  _LogBloc()
      : super(const _S(7), [
          () => UseCaseBuilder(
              typeOfEvent: _LogEvent,
              useCaseGenerator: () => _LoggingUseCase()),
        ]);
}

// ---------------------------------------------------------------------------
// StatefulUseCaseBuilder

class _CountEvent extends EventBase {}

class _InitEvent extends EventBase {}

class _CountingUseCase extends BlocUseCase<_StatefulBloc, _CountEvent> {
  static int created = 0;
  static int closed = 0;
  int calls = 0;

  _CountingUseCase() {
    created++;
  }

  @override
  Future<void> execute(_CountEvent event) async {
    calls++;
    emitUpdate(newState: _S(calls), groupsToRebuild: {'count'});
  }

  @override
  void close() {
    closed++;
    super.close();
  }
}

class _InitUseCase extends BlocUseCase<_StatefulBloc, _InitEvent> {
  @override
  Future<void> execute(_InitEvent event) async {
    emitUpdate(newState: const _S(100));
  }
}

class _StatefulBloc extends JuiceBloc<_S> {
  _StatefulBloc(StatefulUseCaseBuilder builder)
      : super(const _S(), [
          () => builder,
          () => StatefulUseCaseBuilder(
                typeOfEvent: _InitEvent,
                useCaseGenerator: () => _InitUseCase(),
                initialEventBuilder: () => _InitEvent(),
              ),
        ]);
}

// ---------------------------------------------------------------------------
// Inline emitter extras

class _InlineWait extends EventBase {}

class _InlineFail extends EventBase {}

class _InlineCancel extends EventBase {}

class _InlineOld extends EventBase {}

class _InlineNavUpdate extends EventBase {}

class _GroupKey {
  final String id;
  const _GroupKey(this.id);
  @override
  String toString() => 'key-$id';
}

class _InlineBloc extends JuiceBloc<_S> {
  static final navigations = <Map<String, dynamic>>[];
  static int? seenOld;

  _InlineBloc()
      : super(
          const _S(),
          [
            () => InlineUseCaseBuilder<_InlineBloc, _S, _InlineWait>(
                  typeOfEvent: _InlineWait,
                  handler: (ctx, e) async => ctx.emit.waiting(
                    newState: const _S(1),
                    groups: {const _GroupKey('w')},
                  ),
                ),
            () => InlineUseCaseBuilder<_InlineBloc, _S, _InlineFail>(
                  typeOfEvent: _InlineFail,
                  handler: (ctx, e) async =>
                      ctx.emit.failure(newState: const _S(2), groups: {'f'}),
                ),
            () => InlineUseCaseBuilder<_InlineBloc, _S, _InlineCancel>(
                  typeOfEvent: _InlineCancel,
                  handler: (ctx, e) async =>
                      ctx.emit.cancel(newState: const _S(3), groups: {'c'}),
                ),
            () => InlineUseCaseBuilder<_InlineBloc, _S, _InlineOld>(
                  typeOfEvent: _InlineOld,
                  handler: (ctx, e) async {
                    seenOld = ctx.oldState.n;
                    ctx.emit.update(newState: ctx.state.copyWith(n: 50));
                  },
                ),
            () => InlineUseCaseBuilder<_InlineBloc, _S, _InlineNavUpdate>(
                  typeOfEvent: _InlineNavUpdate,
                  handler: (ctx, e) async => ctx.emit.update(
                    newState: const _S(9),
                    groups: {'nav'},
                    aviatorName: 'go',
                    aviatorArgs: {'to': 'update'},
                  ),
                ),
          ],
          [
            () => Aviator(
                name: 'go',
                navigateWhere: (args) {
                  navigations.add(args);
                }),
          ],
        );
}

// ---------------------------------------------------------------------------
// Unhandled events + error handler

class _Unhandled extends EventBase {}

class _BareBloc extends JuiceBloc<_S> {
  _BareBloc(BlocErrorHandler handler)
      : super(const _S(), const [], const [], null, handler);
}

void main() {
  late _CaptureLogger logger;
  setUp(() {
    logger = _CaptureLogger();
    JuiceLoggerConfig.configureLogger(logger);
  });
  tearDown(() => JuiceLoggerConfig.configureLogger(DefaultJuiceLogger()));

  group('BlocUseCase logging helpers', () {
    test('log/logState/logError prefix the use case name and enrich context',
        () async {
      final bloc = _LogBloc();
      await bloc.send(_LogEvent());

      final hello = logger.matching('[_LoggingUseCase] hello').single;
      expect(hello.level, Level.warning);
      expect(hello.context, {
        'useCase': '_LoggingUseCase',
        'bloc': '_LogBloc',
        'extra': 1,
      });

      final plain = logger.matching('[_LoggingUseCase] plain').single;
      expect(plain.level, Level.info);
      expect(plain.context, {'useCase': '_LoggingUseCase', 'bloc': '_LogBloc'});

      final state =
          logger.matching('[_LoggingUseCase] State: after load').single;
      expect(state.context, {
        'useCase': '_LoggingUseCase',
        'bloc': '_LogBloc',
        'state': '_S(7)',
        'k': 'v',
      });

      final errors = logger.matching('[_LoggingUseCase] Exception:').toList();
      expect(errors, hasLength(2));
      expect(errors[0].message, '[_LoggingUseCase] Exception: Bad state: bad');
      expect(errors[0].error, isA<StateError>());
      expect(errors[0].context!['where'], 'x');
      expect(errors[0].context!['state'], '_S(7)');
      expect(errors[1].error, isA<ArgumentError>());
      expect(errors[1].context!.containsKey('where'), isFalse);
      await bloc.close();
    });

    test('useCaseName is the runtime type', () {
      expect(_LoggingUseCase().useCaseName, '_LoggingUseCase');
    });
  });

  group('UpdateUseCase (built-in UpdateEvent handler)', () {
    late _LogBloc bloc;
    setUp(() => bloc = _LogBloc());
    tearDown(() => bloc.close());

    test('onUpdate emits UpdatingStatus with the new state', () async {
      await bloc
          .send(UpdateEvent<_S>(newState: const _S(1), groupsToRebuild: {'g'}));
      expect(bloc.currentStatus, isA<UpdatingStatus<_S>>());
      expect(bloc.state.n, 1);
      expect(bloc.currentStatus.event!.groupsToRebuild, contains('g'));
    });

    test('onWaiting emits WaitingStatus and keeps state when none given',
        () async {
      await bloc.send(UpdateEvent(resetStatusTo: ResetStreamType.onWaiting));
      expect(bloc.currentStatus, isA<WaitingStatus<_S>>());
      expect(bloc.state.n, 7);
    });

    test('onFailure emits FailureStatus with the new state', () async {
      await bloc.send(UpdateEvent<_S>(
        newState: const _S(3),
        resetStatusTo: ResetStreamType.onFailure,
      ));
      expect(bloc.currentStatus, isA<FailureStatus<_S>>());
      expect(bloc.state.n, 3);
      expect(bloc.oldState.n, 7);
    });

    test('UpdateEvent defaults to rebuildAlways groups', () {
      expect(UpdateEvent().groupsToRebuild, rebuildAlways);
      expect(UpdateEvent().resetStatusTo, ResetStreamType.onUpdate);
    });

    test('aviator args are forwarded on update', () async {
      _InlineBloc.navigations.clear();
      final inline = _InlineBloc();
      await inline.send(UpdateEvent(aviatorName: 'go', aviatorArgs: {'a': 1}));
      expect(_InlineBloc.navigations, [
        {'a': 1}
      ]);
      await inline.close();
    });
  });

  group('NoOpUseCase', () {
    test('noOpUseCaseGenerator yields a NoOpUseCase that does nothing',
        () async {
      final uc = noOpUseCaseGenerator();
      expect(uc, isA<NoOpUseCase>());
      await uc.execute(_LogEvent());
      uc.close();
    });
  });

  group('StatefulUseCaseBuilder', () {
    setUp(() {
      _CountingUseCase.created = 0;
      _CountingUseCase.closed = 0;
    });

    test('exposes its configuration', () {
      final b = StatefulUseCaseBuilder(
        typeOfEvent: _CountEvent,
        useCaseGenerator: () => _CountingUseCase(),
        concurrency: EventConcurrency.sequential,
      );
      expect(b.eventType, _CountEvent);
      expect(b.typeOfEvent, _CountEvent);
      expect(b.concurrency, EventConcurrency.sequential);
      expect(b.initialEventBuilder, isNull);
      expect(
          StatefulUseCaseBuilder(
              typeOfEvent: _CountEvent,
              useCaseGenerator: () => _CountingUseCase()).concurrency,
          EventConcurrency.concurrent);
    });

    test('generator returns the same instance until close()', () async {
      final b = StatefulUseCaseBuilder(
        typeOfEvent: _CountEvent,
        useCaseGenerator: () => _CountingUseCase(),
      );
      final first = b.generator();
      expect(b.generator(), same(first));
      expect(_CountingUseCase.created, 1);

      await b.close();
      expect(_CountingUseCase.closed, 1);

      final second = b.generator();
      expect(identical(second, first), isFalse);
      expect(_CountingUseCase.created, 2);
    });

    test('close() before any instance exists is safe', () async {
      final b = StatefulUseCaseBuilder(
        typeOfEvent: _CountEvent,
        useCaseGenerator: () => _CountingUseCase(),
      );
      await b.close();
      expect(_CountingUseCase.closed, 0);
    });

    test('state inside the use case persists across events in a bloc',
        () async {
      final bloc = _StatefulBloc(StatefulUseCaseBuilder(
        typeOfEvent: _CountEvent,
        useCaseGenerator: () => _CountingUseCase(),
      ));
      // initialEventBuilder fired _InitEvent on construction.
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.n, 100);

      await bloc.send(_CountEvent());
      await bloc.send(_CountEvent());
      await bloc.send(_CountEvent());
      expect(bloc.state.n, 3, reason: 'one instance counted all three');
      expect(_CountingUseCase.created, 1);

      await bloc.close();
      expect(_CountingUseCase.closed, 1, reason: 'bloc close closes builder');
    });
  });

  group('InlineUseCaseBuilder emitter extras', () {
    late _InlineBloc bloc;
    setUp(() {
      _InlineBloc.navigations.clear();
      bloc = _InlineBloc();
    });
    tearDown(() => bloc.close());

    test('waiting converts arbitrary group objects via toString', () async {
      await bloc.send(_InlineWait());
      expect(bloc.currentStatus, isA<WaitingStatus<_S>>());
      expect(bloc.state.n, 1);
      expect(bloc.currentStatus.event!.groupsToRebuild, {'key-w'});
    });

    test('failure and cancel emit their status types', () async {
      await bloc.send(_InlineFail());
      expect(bloc.currentStatus, isA<FailureStatus<_S>>());
      expect(bloc.state.n, 2);
      await bloc.send(_InlineCancel());
      expect(bloc.currentStatus, isA<CancelingStatus<_S>>());
      expect(bloc.state.n, 3);
      expect(bloc.currentStatus.event!.groupsToRebuild, {'c'});
    });

    test('ctx.oldState exposes the previous state', () async {
      await bloc.send(_InlineFail()); // 0 -> 2
      await bloc.send(_InlineOld()); // reads oldState (0), then 2 -> 50
      expect(_InlineBloc.seenOld, 0);
      expect(bloc.state.n, 50);
      expect(bloc.oldState.n, 2);
    });

    test('update with aviatorName navigates with args', () async {
      await bloc.send(_InlineNavUpdate());
      expect(bloc.state.n, 9);
      expect(_InlineBloc.navigations, [
        {'to': 'update'}
      ]);
    });
  });

  group('Unhandled events and BlocErrorHandler', () {
    test('send() of an unregistered event reports via the error handler',
        () async {
      final reported = <String>[];
      final logged = <String>[];
      final bloc = _BareBloc(BlocErrorHandler(
        onError: (m, {error, stackTrace}) => reported.add(m),
        logger: logged.add,
      ));
      await bloc.send(_Unhandled());
      expect(reported, ['No use case registered for _Unhandled']);
      expect(logged, reported);
      expect(bloc.currentStatus.event, isNull, reason: 'no emission');
      final err = logger.entries
          .where((e) => e.context?['type'] == 'unhandled_event')
          .single;
      expect(err.error, isA<StateError>());
      expect(err.context!['event'], '_Unhandled');
      await bloc.close();
    });

    test('handleError forwards error + stack and logs them in debug', () {
      Object? gotError;
      StackTrace? gotStack;
      final handler = BlocErrorHandler(onError: (m, {error, stackTrace}) {
        gotError = error;
        gotStack = stackTrace;
      });
      final st = StackTrace.fromString('trace-line');
      handler.handleError('oops', error: 'E1', stackTrace: st);
      expect(gotError, 'E1');
      expect(gotStack, st);
      final messages = logger.entries.map((e) => e.message).toList();
      expect(
          messages,
          containsAllInOrder(
              ['Bloc Error: oops', 'Error: E1', 'StackTrace: trace-line']));
    });

    test('handleError with no callbacks only logs the message', () {
      const BlocErrorHandler().handleError('just a message');
      expect(
          logger.entries.map((e) => e.message), ['Bloc Error: just a message']);
    });

    test('JuiceBlocException / NoEventHandlerException describe themselves',
        () {
      expect(JuiceBlocException('m').toString(), 'BlocException: m');
      final withError = JuiceBlocException('m', error: 'inner');
      expect(withError.toString(), 'BlocException: m\nError: inner');
      final nh = NoEventHandlerException(_BareBloc, _Unhandled);
      expect(nh.blocType, _BareBloc);
      expect(nh.eventType, _Unhandled);
      expect(nh.message,
          'No handler found for bloc _BareBloc and event: _Unhandled');
      expect(nh, isA<JuiceBlocException>());
    });
  });
}
