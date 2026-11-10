import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart'
    show
        JuiceLogger,
        JuiceLoggerConfig,
        JuiceTelemetry,
        JuiceTelemetryKind,
        Level;
import 'package:juice_sync/juice_sync.dart';

/// Controllable executor: behavior keyed by mutation `type`.
class FakeExecutor {
  final List<Mutation> sent = [];
  final Set<String> permanentTypes = {};
  final Map<String, int> retryableTimes = {}; // type -> fails before success
  final Map<String, int> _used = {};

  Future<void> call(Mutation m) async {
    sent.add(m);
    if (permanentTypes.contains(m.type)) {
      throw const PermanentSyncError('permanent');
    }
    final budget = retryableTimes[m.type] ?? 0;
    final used = _used[m.type] ?? 0;
    if (used < budget) {
      _used[m.type] = used + 1;
      throw StateError('transient');
    }
  }
}

class TrackingStore extends InMemorySyncStore {
  bool disposed = false;
  TrackingStore([super.seed = const []]);
  @override
  Future<void> dispose() async => disposed = true;
}

class FailingPutStore extends InMemorySyncStore {
  @override
  Future<void> put(Mutation mutation) async =>
      throw const StorageSyncError('disk full');
}

class FailingLoadStore extends InMemorySyncStore {
  @override
  Future<List<Mutation>> loadAll() async =>
      throw const StorageSyncError('corrupt');
}

/// Counts the flush use cases the bloc starts.
class _FlushCounter implements JuiceLogger {
  int started = 0;

  @override
  void record(JuiceTelemetry e) {
    if (e.kind == JuiceTelemetryKind.useCaseStarted &&
        e.event == 'FlushRequestedEvent') {
      started++;
    }
  }

  @override
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context}) {}

  @override
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) {}
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  SyncBloc build(
    FakeExecutor ex,
    SyncStore store, {
    Stream<bool>? online,
    int maxAttempts = 8,
    Duration initialBackoff = const Duration(milliseconds: 20),
    Duration? periodicRetry,
  }) =>
      SyncBloc.withConfig(SyncConfig(
        executor: ex.call,
        store: store,
        onlineSignal: online,
        maxAttempts: maxAttempts,
        initialBackoff: initialBackoff,
        maxBackoff: const Duration(milliseconds: 200),
        periodicRetry: periodicRetry,
      ));

  group('SyncState model', () {
    test('defaults', () {
      const s = SyncState();
      expect(s.pending, isEmpty);
      expect(s.failed, isEmpty);
      expect(s.online, isTrue);
      expect(s.processedCount, 0);
    });
  });

  group('Enqueue + drain', () {
    test('enqueue persists, returns the mutation, and drains when online',
        () async {
      final ex = FakeExecutor();
      final store = InMemorySyncStore();
      final bloc = build(ex, store);
      await settle();

      final m = await bloc.enqueue('a', {'x': 1});
      expect(m.type, 'a');
      await settle();

      expect(ex.sent.map((x) => x.type), contains('a'));
      expect(bloc.state.pending, isEmpty);
      expect(bloc.state.processedCount, 1);
      expect(await store.loadAll(), isEmpty);
      await bloc.close();
    });

    test('drains in seq order', () async {
      final ex = FakeExecutor();
      final bloc = build(ex, InMemorySyncStore());
      await settle();

      await bloc.enqueue('first', {});
      await bloc.enqueue('second', {});
      await bloc.enqueue('third', {});
      await settle();

      expect(ex.sent.map((m) => m.type), ['first', 'second', 'third']);
      await bloc.close();
    });
  });

  group('Selective refresh', () {
    test('enqueue targets only that mutation\'s group', () async {
      final ex = FakeExecutor();
      final onlineCtrl = StreamController<bool>.broadcast();
      final bloc = build(ex, InMemorySyncStore(), online: onlineCtrl.stream);
      await settle();
      onlineCtrl.add(false); // stay offline so enqueues don't flush
      await settle();

      final a = await bloc.enqueue('a', {});
      await settle();

      final emissions = <Set<String>>[];
      final sub = bloc.stream.listen((s) {
        final g = s.event?.groupsToRebuild;
        if (g != null) emissions.add(g);
      });

      final b = await bloc.enqueue('b', {}); // its own event
      await settle();

      final mutA = SyncGroups.mutation(a.id);
      final mutB = SyncGroups.mutation(b.id);
      // Enqueuing b targets b's group and never a's.
      expect(emissions.any((g) => g.contains(mutB)), isTrue);
      expect(emissions.every((g) => !g.contains(mutA)), isTrue);

      await sub.cancel();
      await onlineCtrl.close();
      await bloc.close();
    });
  });

  group('Failure handling', () {
    test('permanent failure → dead-letter; queue continues', () async {
      final ex = FakeExecutor()..permanentTypes.add('bad');
      final bloc = build(ex, InMemorySyncStore());
      await settle();

      await bloc.enqueue('bad', {});
      await bloc.enqueue('good', {});
      await settle();

      expect(bloc.state.failed.map((m) => m.type), ['bad']);
      expect(bloc.state.pending, isEmpty);
      expect(ex.sent.map((m) => m.type), contains('good'));
      await bloc.close();
    });

    test('retryable failure backs off then succeeds', () async {
      final ex = FakeExecutor()..retryableTimes['flaky'] = 1;
      final bloc = build(ex, InMemorySyncStore(),
          initialBackoff: const Duration(milliseconds: 80));
      await settle();

      await bloc.enqueue('flaky', {});
      await settle(); // 20ms < 80ms backoff: first attempt failed, still pending
      expect(bloc.state.pending.length, 1);
      expect(bloc.state.pending.first.attempts, 1);

      await settle(140); // backoff fires → retry succeeds
      expect(bloc.state.pending, isEmpty);
      expect(bloc.state.processedCount, 1);
      await bloc.close();
    });

    test('max attempts → dead-letter (queue not wedged)', () async {
      final ex = FakeExecutor()..retryableTimes['poison'] = 1000;
      final bloc = build(ex, InMemorySyncStore(),
          maxAttempts: 2, initialBackoff: const Duration(milliseconds: 10));
      await settle();

      await bloc.enqueue('poison', {});
      await settle(120); // attempt 1 + backoff + attempt 2 → dead-letter

      expect(bloc.state.failed.map((m) => m.type), ['poison']);
      expect(bloc.state.pending, isEmpty);
      await bloc.close();
    });
  });

  group('Partitioned ordering', () {
    test('a blocked orderingKey holds its siblings; independents proceed',
        () async {
      final ex = FakeExecutor()
        ..retryableTimes['head'] = 1000; // head always fails
      final bloc = build(ex, InMemorySyncStore(),
          initialBackoff: const Duration(milliseconds: 200));
      await settle();

      await bloc.enqueue('head', {}, orderingKey: 'P');
      await bloc.enqueue('tail', {}, orderingKey: 'P');
      await bloc.enqueue('indep', {});
      await settle(); // one pass, head blocks partition P

      final sentTypes = ex.sent.map((m) => m.type).toSet();
      expect(sentTypes, contains('head'));
      expect(sentTypes, contains('indep')); // independent partition proceeded
      expect(sentTypes, isNot(contains('tail'))); // blocked behind head
      expect(
          bloc.state.pending.map((m) => m.type), containsAll(['head', 'tail']));
      await bloc.close();
    });
  });

  group('Crash recovery', () {
    test('a persisted inFlight mutation is recovered and re-sent', () async {
      final store = InMemorySyncStore([
        Mutation(
          id: 'r1',
          seq: 0,
          type: 'recover',
          payload: const {},
          createdAt: DateTime(2026),
          status: MutationStatus.inFlight,
        ),
      ]);
      final ex = FakeExecutor();
      final bloc = build(ex, store);
      await settle();

      expect(ex.sent.map((m) => m.type), contains('recover'));
      expect(bloc.state.pending, isEmpty);
      expect(bloc.state.processedCount, 1);
      await bloc.close();
    });
  });

  group('Fail-loud storage', () {
    test('put failure throws out of enqueue', () async {
      final bloc = build(FakeExecutor(), FailingPutStore());
      await settle();
      await expectLater(
          bloc.enqueue('x', {}), throwsA(isA<StorageSyncError>()));
      await bloc.close();
    });

    test('loadAll failure → error status (not silently empty)', () async {
      final bloc = build(FakeExecutor(), FailingLoadStore());
      await settle();
      expect(bloc.state.status, SyncStatus.error);
      expect(bloc.state.lastError, isNotNull);
      await bloc.close();
    });
  });

  group('Online gating', () {
    test('offline queues without sending; online edge flushes', () async {
      final ex = FakeExecutor();
      final onlineCtrl = StreamController<bool>.broadcast();
      final bloc = build(ex, InMemorySyncStore(), online: onlineCtrl.stream);
      await settle();
      onlineCtrl.add(false);
      await settle();

      await bloc.enqueue('q', {});
      await settle();
      expect(ex.sent, isEmpty);
      expect(bloc.state.pending.length, 1);

      onlineCtrl.add(true);
      await settle();
      expect(ex.sent.map((m) => m.type), contains('q'));
      expect(bloc.state.pending, isEmpty);

      await onlineCtrl.close();
      await bloc.close();
    });

    test('a manual flush while offline sends nothing and spends no attempt',
        () async {
      final ex = FakeExecutor();
      final store = InMemorySyncStore();
      final onlineCtrl = StreamController<bool>.broadcast();
      final bloc = build(ex, store, online: onlineCtrl.stream);
      await settle();
      onlineCtrl.add(false);
      await settle();

      await bloc.enqueue('q', {});
      await settle(); // the mutation is in the queue before the flush runs
      expect(bloc.state.pending.length, 1);
      bloc.flush();
      await settle();

      expect(ex.sent, isEmpty);
      expect(bloc.state.pending.single.attempts, 0);
      expect(bloc.state.pending.single.status, MutationStatus.pending);
      expect((await store.loadAll()).single.attempts, 0);
      expect(bloc.state.status, SyncStatus.idle);

      await onlineCtrl.close();
      await bloc.close();
    });

    test(
        'the periodic retry asks for a flush on its interval with nothing '
        'else asking, and stops when the bloc closes', () async {
      final flushes = _FlushCounter();
      final saved = JuiceLoggerConfig.logger;
      JuiceLoggerConfig.configureLogger(flushes);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final bloc = build(
        FakeExecutor(),
        InMemorySyncStore(),
        periodicRetry: const Duration(milliseconds: 20),
      );
      await settle(30);
      final before = flushes.started;

      // An idle, online, empty queue: only the interval asks.
      await settle(130);
      expect(flushes.started - before, greaterThanOrEqualTo(3));

      await bloc.close();
      final atClose = flushes.started;
      await settle(80);
      expect(flushes.started, atClose);
    });

    test('the periodic retry while offline never dead-letters the queue',
        () async {
      // Every send fails, so a flush that ran offline would spend all three
      // attempts and dead-letter the mutation well inside the wait below.
      final ex = FakeExecutor()..retryableTimes['q'] = 1000;
      final onlineCtrl = StreamController<bool>.broadcast();
      final bloc = build(
        ex,
        InMemorySyncStore(),
        online: onlineCtrl.stream,
        maxAttempts: 3,
        initialBackoff: const Duration(milliseconds: 5),
        periodicRetry: const Duration(milliseconds: 10),
      );
      await settle();
      onlineCtrl.add(false);
      await settle();

      await bloc.enqueue('q', {});
      await settle(200);

      expect(ex.sent, isEmpty);
      expect(bloc.state.failed, isEmpty);
      expect(bloc.state.pending.single.attempts, 0);

      await onlineCtrl.close();
      await bloc.close();
    });

    test(
        'a backoff timer that fires while offline sends nothing; the online '
        'edge resends', () async {
      final ex = FakeExecutor()..retryableTimes['q'] = 1;
      final onlineCtrl = StreamController<bool>.broadcast();
      final bloc = build(
        ex,
        InMemorySyncStore(),
        online: onlineCtrl.stream,
        initialBackoff: const Duration(milliseconds: 60),
      );
      await settle();

      await bloc.enqueue('q', {});
      await settle();
      expect(ex.sent.length, 1); // failed once; the backoff timer is armed
      expect(bloc.state.pending.single.attempts, 1);

      onlineCtrl.add(false);
      await settle(150); // the backoff timer fires in here, offline

      expect(ex.sent.length, 1);
      expect(bloc.state.pending.single.attempts, 1);

      onlineCtrl.add(true);
      await settle();
      expect(ex.sent.length, 2);
      expect(bloc.state.pending, isEmpty);
      expect(bloc.state.processedCount, 1);

      await onlineCtrl.close();
      await bloc.close();
    });

    test('going offline mid-pass stops the pass before its next send',
        () async {
      final onlineCtrl = StreamController<bool>.broadcast();
      final sent = <Mutation>[];
      final bloc = SyncBloc.withConfig(SyncConfig(
        store: InMemorySyncStore(),
        onlineSignal: onlineCtrl.stream,
        executor: (m) async {
          sent.add(m);
          if (sent.length == 1) {
            // The link drops while the first send is in the air.
            onlineCtrl.add(false);
            await settle();
          }
        },
      ));
      await settle();
      onlineCtrl.add(false);
      await settle();

      await bloc.enqueue('a', {});
      await bloc.enqueue('b', {});
      await settle();
      expect(sent, isEmpty);

      onlineCtrl.add(true); // one pass over both mutations starts
      await settle(80);

      expect(sent.map((m) => m.type), ['a']);
      expect(bloc.state.online, isFalse);
      expect(bloc.state.pending.single.type, 'b');
      expect(bloc.state.pending.single.attempts, 0);
      expect(bloc.state.status, SyncStatus.idle);

      onlineCtrl.add(true);
      await settle();
      expect(sent.map((m) => m.type), ['a', 'b']);
      expect(bloc.state.pending, isEmpty);

      await onlineCtrl.close();
      await bloc.close();
    });
  });

  group('Retry / discard / lifecycle', () {
    test('retryFailed moves a dead-letter back to pending and resends',
        () async {
      final ex = FakeExecutor()..permanentTypes.add('x');
      final bloc = build(ex, InMemorySyncStore());
      await settle();

      await bloc.enqueue('x', {});
      await settle();
      expect(bloc.state.failed.length, 1);

      ex.permanentTypes.clear(); // now it will succeed
      bloc.retryFailed();
      await settle();

      expect(bloc.state.failed, isEmpty);
      expect(bloc.state.processedCount, 1);
      await bloc.close();
    });

    test('discard removes and durably deletes', () async {
      final ex = FakeExecutor();
      final store = InMemorySyncStore();
      final onlineCtrl = StreamController<bool>.broadcast();
      final bloc = build(ex, store, online: onlineCtrl.stream);
      await settle();
      onlineCtrl.add(false);
      await settle();

      final m = await bloc.enqueue('d', {});
      bloc.discard(m.id);
      await settle();

      expect(bloc.state.pending, isEmpty);
      expect(await store.loadAll(), isEmpty);
      await onlineCtrl.close();
      await bloc.close();
    });

    test('close disposes the store', () async {
      final store = TrackingStore();
      final bloc = build(FakeExecutor(), store);
      await settle();
      await bloc.close();
      expect(store.disposed, isTrue);
    });
  });

  concurrencyModeTests();
}

// ---------------------------------------------------------------------------
// Concurrency modes (0.2.0, ISSUES #22): gated fakes prove the mode chosen for
// each event, the way the rest of the family pins theirs.
// ---------------------------------------------------------------------------

/// loadAll blocks on [gate] and counts calls — proves `droppable` init.
class GatedLoadStore extends InMemorySyncStore {
  Completer<void>? gate;
  int loads = 0;
  @override
  Future<List<Mutation>> loadAll() async {
    loads++;
    if (gate != null) await gate!.future;
    return super.loadAll();
  }
}

/// put blocks on [gate] and counts calls — proves `sequential` retries.
class GatedPutStore extends InMemorySyncStore {
  GatedPutStore([super.seed = const []]);
  Completer<void>? gate;
  int puts = 0;
  @override
  Future<void> put(Mutation mutation) async {
    puts++;
    if (gate != null) await gate!.future;
    return super.put(mutation);
  }
}

/// The executor blocks while sending [gatedType] — holds a flush mid-pass.
class GatedExecutor extends FakeExecutor {
  String? gatedType;
  Completer<void>? gate;
  @override
  Future<void> call(Mutation m) async {
    await super.call(m);
    if (m.type == gatedType && gate != null) await gate!.future;
  }
}

Mutation _failed(String id, int seq) => Mutation(
      id: id,
      seq: seq,
      type: 't',
      payload: const {},
      createdAt: DateTime(2026),
      status: MutationStatus.failed,
      attempts: 3,
    );

void concurrencyModeTests() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('Concurrency modes (0.2.0)', () {
    test('overlapping initializations coalesce to ONE loadAll (droppable)',
        () async {
      final ex = FakeExecutor();
      final store = GatedLoadStore()..gate = Completer<void>();
      SyncConfig cfg() => SyncConfig(executor: ex.call, store: store);

      final bloc = SyncBloc();
      bloc.send(InitializeSyncEvent(config: cfg()));
      await settle(1); // first init is now waiting inside loadAll
      bloc.send(InitializeSyncEvent(config: cfg()));
      await settle(1);

      expect(store.loads, 1, reason: 'the second init mid-load is dropped');

      store.gate!.complete();
      store.gate = null;
      await settle();
      expect(bloc.state.status, isNot(SyncStatus.loading));
      await bloc.close();
    });

    test('overlapping retries serialize: the second put waits (sequential)',
        () async {
      final ex = FakeExecutor();
      final store = GatedPutStore([_failed('A', 0), _failed('B', 1)]);
      final bloc = SyncBloc.withConfig(SyncConfig(
        executor: ex.call,
        store: store,
        onlineSignal: Stream<bool>.value(false), // stay offline: no drain
      ));
      await settle();
      expect(bloc.state.failed.map((m) => m.id), ['A', 'B']);
      final putsAfterInit = store.puts;

      store.gate = Completer<void>();
      bloc.retryFailed('A');
      await settle(1); // A's revive is now waiting inside put
      bloc.retryFailed('B');
      await settle(1);

      expect(store.puts, putsAfterInit + 1,
          reason: "B's retry must not start until A's completes");

      store.gate!.complete();
      store.gate = null;
      await settle();
      expect(bloc.state.failed, isEmpty);
      expect(bloc.state.pending.map((m) => m.id), ['A', 'B']);
      expect(store.puts, putsAfterInit + 2);
      await bloc.close();
    });

    test(
        'a mutation enqueued MID-FLUSH is sent by the same flush (re-run flag)',
        () async {
      final ex = GatedExecutor()
        ..gatedType = 'a'
        ..gate = Completer<void>();
      final bloc = SyncBloc.withConfig(SyncConfig(
        executor: ex.call,
        store: InMemorySyncStore(),
        // no periodicRetry: only the re-run flag can drain 'b'
      ));
      await settle();

      await bloc.enqueue('a', {});
      await settle(1); // flush is holding on send('a')
      await bloc.enqueue('b', {}); // its FlushRequested hits the guard → flag
      await settle(1);
      expect(ex.sent.map((m) => m.type), ['a'],
          reason: "b waits; the pass is still inside 'a'");

      ex.gate!.complete();
      ex.gate = null;
      await settle();

      expect(ex.sent.map((m) => m.type), ['a', 'b'],
          reason: 'the re-run pass drained b with no further trigger');
      expect(bloc.state.pending, isEmpty);
      await bloc.close();
    });
  });
}
