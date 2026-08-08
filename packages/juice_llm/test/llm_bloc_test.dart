import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_llm/juice_llm.dart';

/// A fully controllable [LlmProvider]: a generation emits [scriptedWords] one
/// at a time with a controllable delay, honoring cancellation; load/embed
/// behavior is configurable to drive the fail-loud paths.
class FakeLlmProvider implements LlmProvider {
  FakeLlmProvider({
    this.scriptedWords = const ['one', 'two', 'three'],
    this.perToken = const Duration(milliseconds: 5),
    this.capabilities = const {LlmCapability.text, LlmCapability.embeddings},
  });

  List<String> scriptedWords;
  Duration perToken;
  @override
  Set<LlmCapability> capabilities;

  Object? loadError; // set → load() throws (OOM/format mismatch)
  Object? generateError; // set → generate stream errors after first chunk
  bool loaded = false;
  bool disposed = false;
  int generateCalls = 0;

  /// Completes when a generate stream is cancelled (listener cancel).
  final List<String> cancelledOrder = [];

  @override
  String get name => 'fake';

  @override
  Future<void> load(String modelPath, LlmLoadOptions options) async {
    if (loadError != null) throw loadError!;
    loaded = true;
  }

  @override
  Future<void> unload() async => loaded = false;

  @override
  Stream<LlmChunk> generate(LlmRequest request) async* {
    generateCalls++;
    if (!loaded) throw const LlmProviderException('not loaded');
    try {
      for (var i = 0; i < scriptedWords.length; i++) {
        await Future<void>.delayed(perToken);
        if (generateError != null && i == 1) throw generateError!;
        final last = i == scriptedWords.length - 1;
        yield LlmChunk(i == 0 ? scriptedWords[i] : ' ${scriptedWords[i]}',
            tokens: 1, done: last);
      }
    } finally {
      // async* runs finally on cancellation — record it for assertions.
      cancelledOrder.add(request.requestId);
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    if (!capabilities.contains(LlmCapability.embeddings)) {
      throw UnsupportedError('no embeddings');
    }
    return [text.length.toDouble(), 1.0, 2.0];
  }

  @override
  Future<void> dispose() async => disposed = true;
}

LlmModel _model({Set<LlmCapability> caps = const {LlmCapability.text}}) =>
    LlmModel(
      id: 'fake-1',
      displayName: 'Fake',
      source: Uri.parse('file:///fake'),
      sha256: 'abc',
      sizeBytes: 1,
      capabilities: caps,
    );

/// A ModelSource that "downloads" instantly, emitting an int-fraction progress
/// then a terminal event — exercises the fetch lifecycle headlessly.
class _FakeModelSource implements ModelSource {
  @override
  Stream<ModelFetchProgress> fetch(LlmModel model, String path) async* {
    yield const ModelFetchProgress(
        fraction: 0.5, receivedBytes: 5, totalBytes: 10);
    yield const ModelFetchProgress(
        fraction: 1, receivedBytes: 10, totalBytes: 10, done: true);
  }

  @override
  Future<bool> isPresent(LlmModel model, String path) async => false;

  @override
  Future<void> delete(LlmModel model, String path) async {}
}


/// A provider stuck in "prefill": generate never yields a chunk, and — like
/// a native runtime wedged mid-call — its cancel can never reach a yield
/// boundary, so the subscription's cancel future never completes.
class WedgedProvider extends FakeLlmProvider {
  final started = Completer<void>();

  @override
  Stream<LlmChunk> generate(LlmRequest request) async* {
    generateCalls++;
    if (!started.isCompleted) started.complete();
    // Await forever INSIDE the generator body: no yield boundary is ever
    // reached, so cancellation can never take effect.
    await Completer<void>().future;
  }
}

/// A provider stuck mid-call until the TEST releases it — the 2026-08-08
/// field shape: a mid-prefill stop whose teardown returned 89s later, well
/// after the wedge was declared. Completing [release] is the native thread
/// coming back.
class LateTeardownProvider extends FakeLlmProvider {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Stream<LlmChunk> generate(LlmRequest request) async* {
    generateCalls++;
    if (!started.isCompleted) started.complete();
    await release.future;
  }
}

void main() {
  Future<void> settle([int ms = 30]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  // Load the Echo/fake model so the bloc is `ready` before generating.
  Future<void> ready(LlmBloc bloc, {LlmModel? model}) async {
    bloc.loadModel(model ?? _model());
    await settle();
    expect(bloc.state.isReady, isTrue, reason: 'model should be ready');
  }

  group('LlmState model', () {
    test('initial is absent with no sessions', () {
      const s = LlmState();
      expect(s.modelStatus, LlmModelStatus.absent);
      expect(s.sessions, isEmpty);
      expect(s.isReady, isFalse);
    });

    test('copyWith accepts an int fetchProgress (regression)', () {
      // FetchModelUseCase emits fetchProgress: 0 (int); copyWith must coerce.
      const s = LlmState();
      expect(s.copyWith(fetchProgress: 0).fetchProgress, 0.0);
      expect(s.copyWith(fetchProgress: 0.5).fetchProgress, 0.5);
    });
  });

  group('Model fetch lifecycle', () {
    test('fetchModel runs absent → fetching → fetched (no int/double crash)',
        () async {
      final fake = FakeLlmProvider();
      final bloc = LlmBloc.withConfig(LlmConfig(
        provider: fake,
        modelSource: _FakeModelSource(),
        resolvePath: (m) => '/tmp/${m.id}.gguf',
      ));
      await settle();

      bloc.fetchModel(_model());
      await settle(60);

      expect(bloc.state.modelStatus, LlmModelStatus.fetched);
      expect(bloc.state.error, isNull);

      await bloc.close();
    });
  });

  group('Lifecycle', () {
    test('load → ready; unload → absent', () async {
      final fake = FakeLlmProvider();
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();

      bloc.loadModel(_model());
      await settle();
      expect(bloc.state.modelStatus, LlmModelStatus.ready);
      expect(fake.loaded, isTrue);

      bloc.unloadModel();
      await settle();
      expect(bloc.state.modelStatus, LlmModelStatus.absent);
      expect(fake.loaded, isFalse);

      await bloc.close();
    });

    test('load failure is loud (error status, no fallback)', () async {
      final fake = FakeLlmProvider()..loadError = StateError('OOM');
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();

      bloc.loadModel(_model());
      await settle();
      expect(bloc.state.modelStatus, LlmModelStatus.error);
      expect(bloc.state.error, contains('OOM'));

      await bloc.close();
    });

    test('close disposes the provider', () async {
      final fake = FakeLlmProvider();
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      await bloc.close();
      expect(fake.disposed, isTrue);
    });
  });

  group('Generation', () {
    test('streams chunks then completes; session is done with full text',
        () async {
      final fake = FakeLlmProvider(scriptedWords: ['a', 'b', 'c']);
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      await ready(bloc);

      bloc.generate(const LlmRequest(
          requestId: 'r1', messages: [LlmMessage.user('hi')]));
      await settle(120);

      final s = bloc.state.sessions['r1']!;
      expect(s.status, SessionStatus.done);
      expect(s.text, 'a b c');
      expect(s.tokens, 3);

      await bloc.close();
    });

    test('generate with no model loaded fails loud (no silent wait)',
        () async {
      final fake = FakeLlmProvider();
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle(); // not loaded

      bloc.generate(const LlmRequest(
          requestId: 'r1', messages: [LlmMessage.user('hi')]));
      await settle();

      final s = bloc.state.sessions['r1']!;
      expect(s.status, SessionStatus.failed);
      expect(s.error, contains('No model loaded'));
      expect(fake.generateCalls, 0); // never reached the runtime

      await bloc.close();
    });

    test('sequential: two generations run in order, not interleaved',
        () async {
      final fake = FakeLlmProvider(scriptedWords: ['x', 'y']);
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      await ready(bloc);

      bloc.generate(const LlmRequest(
          requestId: 'r1', messages: [LlmMessage.user('1')]));
      bloc.generate(const LlmRequest(
          requestId: 'r2', messages: [LlmMessage.user('2')]));
      await settle(150);

      // Both completed; r1 finished before r2 started (cancel/finish order).
      expect(bloc.state.sessions['r1']!.status, SessionStatus.done);
      expect(bloc.state.sessions['r2']!.status, SessionStatus.done);
      expect(fake.cancelledOrder, ['r1', 'r2']); // finally ran r1 then r2

      await bloc.close();
    });

    test('generation error → failed session with the error', () async {
      final fake = FakeLlmProvider(scriptedWords: ['a', 'b', 'c'])
        ..generateError = StateError('decode blew up');
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      await ready(bloc);

      bloc.generate(const LlmRequest(
          requestId: 'r1', messages: [LlmMessage.user('hi')]));
      await settle(120);

      final s = bloc.state.sessions['r1']!;
      expect(s.status, SessionStatus.failed);
      expect(s.error, contains('decode blew up'));

      await bloc.close();
    });
  });

  group('Cancellation', () {
    test('cancel mid-stream → cancelled session + runtime stopped', () async {
      final fake = FakeLlmProvider(
          scriptedWords: ['a', 'b', 'c', 'd', 'e'],
          perToken: const Duration(milliseconds: 25));
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      await ready(bloc);

      bloc.generate(const LlmRequest(
          requestId: 'r1', messages: [LlmMessage.user('hi')]));
      await settle(40); // a couple tokens in
      expect(bloc.isGenerating, isTrue);

      bloc.cancel('r1');
      await settle(80);

      final s = bloc.state.sessions['r1']!;
      expect(s.status, SessionStatus.cancelled);
      expect(bloc.isGenerating, isFalse);
      expect(fake.cancelledOrder, contains('r1')); // generator's finally ran
      // Partial text was kept, not the full script.
      expect(s.text.split(' ').length, lessThan(5));

      await bloc.close();
    });

    test('cancel of unknown/finished id is a no-op', () async {
      final fake = FakeLlmProvider();
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      await ready(bloc);

      bloc.cancel('does-not-exist'); // must not throw / wedge anything
      await settle();
      expect(bloc.isGenerating, isFalse);

      await bloc.close();
    });
  });

  group('Fail-loud guards', () {
    test('cannot load while generating', () async {
      final fake = FakeLlmProvider(
          scriptedWords: ['a', 'b', 'c', 'd'],
          perToken: const Duration(milliseconds: 25));
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      await ready(bloc);

      bloc.generate(const LlmRequest(
          requestId: 'r1', messages: [LlmMessage.user('hi')]));
      await settle(30);
      expect(bloc.isGenerating, isTrue);

      bloc.loadModel(_model()); // should be refused
      await settle(10);
      expect(bloc.state.error, contains('Cannot load'));

      bloc.cancel('r1');
      await settle(60);
      await bloc.close();
    });
  });

  group('Embeddings', () {
    test('embed returns a vector when supported', () async {
      final fake = FakeLlmProvider(
          capabilities: {LlmCapability.text, LlmCapability.embeddings});
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      await ready(bloc,
          model: _model(
              caps: {LlmCapability.text, LlmCapability.embeddings}));

      final v = await bloc.embed('hello');
      expect(v, isNotEmpty);
      expect(v.first, 5.0); // 'hello'.length

      await bloc.close();
    });

    test('embed without capability fails loud', () async {
      final fake = FakeLlmProvider(capabilities: {LlmCapability.text});
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      await ready(bloc);

      await expectLater(bloc.embed('x'), throwsUnsupportedError);

      await bloc.close();
    });

    test('embed with no model loaded fails loud', () async {
      final fake = FakeLlmProvider();
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();

      await expectLater(bloc.embed('x'), throwsStateError);

      await bloc.close();
    });
  });

  group('Session retention', () {
    test('terminal sessions evict beyond the cap (oldest first)', () async {
      final fake = FakeLlmProvider(
          scriptedWords: ['a'], perToken: const Duration(milliseconds: 2));
      final bloc = LlmBloc.withConfig(
          LlmConfig(provider: fake, maxRetainedSessions: 2));
      await settle();
      await ready(bloc);

      for (final id in ['r1', 'r2', 'r3']) {
        bloc.generate(LlmRequest(
            requestId: id, messages: const [LlmMessage.user('x')]));
        await settle(20);
      }
      await settle(40);

      // Only the 2 most-recent terminal sessions are retained.
      expect(bloc.state.sessions.keys.toSet(), {'r2', 'r3'});

      await bloc.close();
    });

    test('explicit evict drops a terminal session', () async {
      final fake = FakeLlmProvider(scriptedWords: ['a']);
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      await ready(bloc);

      bloc.generate(const LlmRequest(
          requestId: 'r1', messages: [LlmMessage.user('x')]));
      await settle(40);
      expect(bloc.state.sessions.containsKey('r1'), isTrue);

      bloc.evictSession('r1');
      await settle();
      expect(bloc.state.sessions.containsKey('r1'), isFalse);

      await bloc.close();
    });
  });

  group('Throttled streaming', () {
    test('many fast tokens coalesce to far fewer emissions', () async {
      // 20 tokens at 5ms = 100ms of streaming; 50ms throttle ⇒ a handful of
      // emissions, not 20.
      final fake = FakeLlmProvider(
        scriptedWords: List.generate(20, (i) => 'w$i'),
        perToken: const Duration(milliseconds: 5),
      );
      final bloc = LlmBloc.withConfig(LlmConfig(
        provider: fake,
        streamThrottle: const Duration(milliseconds: 50),
      ));
      await settle();
      await ready(bloc);

      var genEmissions = 0;
      final sub = bloc.stream.listen((status) {
        final g = status.event?.groupsToRebuild;
        if (g != null && g.contains(LlmGroups.gen('r1'))) genEmissions++;
      });

      bloc.generate(const LlmRequest(
          requestId: 'r1', messages: [LlmMessage.user('hi')]));
      await settle(250);

      // Full text still intact despite coalescing.
      final s = bloc.state.sessions['r1']!;
      expect(s.status, SessionStatus.done);
      expect(s.text.split(' ').length, 20);
      // Coalesced: well under one-emit-per-token (20). Generous bound to avoid
      // timing flakiness, but proves the throttle fires.
      expect(genEmissions, lessThan(12),
          reason: 'throttle should coalesce 20 tokens to a handful');

      await sub.cancel();
      await bloc.close();
    });
  });


  group('beginGeneration serialization (0.2.1)', () {
    test('two direct awaiters take FIFO turns, never interleaved', () async {
      final fake = FakeLlmProvider(perToken: const Duration(milliseconds: 8));
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await ready(bloc);

      // Both begin immediately — the second must not reach the provider until
      // the first's stream has fully finished.
      final order = <String>[];
      final a = bloc.beginGeneration(
        LlmRequest(requestId: 'well-1', messages: [LlmMessage.user('a')]),
        onChunk: (_) => order.add('a'),
      );
      final b = bloc.beginGeneration(
        LlmRequest(requestId: 'chat-1', messages: [LlmMessage.user('b')]),
        onChunk: (_) => order.add('b'),
      );
      final outcomes = await Future.wait([a, b]);

      expect(outcomes[0].kind, GenOutcomeKind.done);
      expect(outcomes[1].kind, GenOutcomeKind.done);
      expect(fake.generateCalls, 2);
      // Every 'a' chunk precedes every 'b' chunk — no interleaving.
      expect(order.join(), matches(RegExp(r'^a+b+$')));
      await bloc.close();
    });

    test('stopGeneration preempts the active stream; the queued one still runs',
        () async {
      final fake = FakeLlmProvider(
          scriptedWords: List.filled(50, 'w'),
          perToken: const Duration(milliseconds: 10));
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await ready(bloc);

      final a = bloc.beginGeneration(
        LlmRequest(requestId: 'well-1', messages: [LlmMessage.user('a')]),
        onChunk: (_) {},
      );
      await settle(25); // let the background stream get going
      expect(bloc.activeRequestId, 'well-1');

      // The interactive pattern: preempt the background lane, then generate.
      final chatChunks = <String>[];
      final stopped = await bloc.stopGeneration();
      expect(stopped, 'well-1');
      final b = bloc.beginGeneration(
        LlmRequest(requestId: 'chat-1', messages: [LlmMessage.user('b')]),
        onChunk: (c) => chatChunks.add(c.textDelta),
      );

      expect((await a).kind, GenOutcomeKind.cancelled);
      expect((await b).kind, GenOutcomeKind.done);
      expect(chatChunks, isNotEmpty);
      await bloc.close();
    });
  });

  group('EngineLease', () {
    test('beginGeneration queues behind a held lease; release frees it',
        () async {
      final llm = LlmBloc.withConfig(LlmConfig());
      await Future<void>.delayed(const Duration(milliseconds: 50)); // init
      final lease = await llm.acquireEngine();
      expect(llm.engineLeased, isTrue);

      var completed = false;
      final gen = llm
          .beginGeneration(
            LlmRequest(
                requestId: 'lease-t1',
                messages: [LlmMessage.user('hello')]),
            onChunk: (_) {},
          )
          .then((o) {
        completed = true;
        return o;
      });
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(completed, isFalse,
          reason: 'a generation must WAIT while the engine is leased');

      lease.release();
      expect(llm.engineLeased, isFalse);
      // The LEASE contract is ordering, not generation success (no model is
      // loaded here) — after release the queued generation must COMPLETE.
      await gen.timeout(const Duration(seconds: 5));
      expect(completed, isTrue);
      lease.release(); // idempotent
      await llm.close();
    });

    test('acquire waits for the in-flight generation', () async {
      final llm = LlmBloc.withConfig(LlmConfig());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final gen = llm.beginGeneration(
        LlmRequest(
            requestId: 'lease-t2', messages: [LlmMessage.user('hi')]),
        onChunk: (_) {},
      );
      final lease = await llm.acquireEngine();
      // Acquisition resolving implies the queue ahead of us drained — the
      // generation's future must already be settled (any outcome).
      await gen.timeout(const Duration(milliseconds: 100));
      lease.release();
      await llm.close();
    });
  });

  group('Safe-point preempt + non-hanging stop (2026-07-30)', () {
    test('stopGeneration returns even when the provider cancel hangs',
        () async {
      final fake = WedgedProvider();
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      fake.loaded = true;

      final outcome = bloc.beginGeneration(
          LlmRequest(requestId: 'well-1', messages: const []),
          onChunk: (_) {});
      await fake.started.future;

      // The old form awaited the generator teardown — with a wedged native
      // call that await NEVER completed and the caller hung forever.
      final id = await bloc.stopGeneration()
          .timeout(const Duration(seconds: 2));
      expect(id, 'well-1');
      expect((await outcome).kind, GenOutcomeKind.cancelled);
    });

    test('preemptAtSafePoint waits out prefill, cancels at first chunk',
        () async {
      final fake = FakeLlmProvider(
          scriptedWords: List.filled(40, 'w'),
          perToken: const Duration(milliseconds: 30));
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      fake.loaded = true;

      final chunks = <LlmChunk>[];
      final outcome = bloc.beginGeneration(
          LlmRequest(requestId: 'well-2', messages: const []),
          onChunk: chunks.add);
      await settle(1); // let the queue start it (registration is chained)
      // The first chunk is still ~30ms away ("prefill") — the preempt
      // must WAIT for it, then cancel.
      final freed = await bloc.preemptAtSafePoint(
          where: (id) => id.startsWith('well-'));
      expect(freed, isTrue);
      expect(chunks, isNotEmpty, reason: 'never cancels before a chunk');
      expect((await outcome).kind, GenOutcomeKind.cancelled);
      expect(chunks.length, lessThan(40),
          reason: 'cancelled mid-decode, not run to completion');
    });

    test('preemptAtSafePoint leaves a still-prefilling generation past '
        'patience (never a wedge-window cancel)', () async {
      final fake = WedgedProvider();
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      fake.loaded = true;

      unawaited(bloc.beginGeneration(
          LlmRequest(requestId: 'well-3', messages: const []),
          onChunk: (_) {}));
      await fake.started.future;

      final freed = await bloc.preemptAtSafePoint(
          where: (id) => id.startsWith('well-'),
          patience: const Duration(milliseconds: 200));
      expect(freed, isFalse, reason: 'no chunk ever came — leave it be');
      expect(bloc.activeRequestId, 'well-3',
          reason: 'the generation was NOT cancelled');
    });

    test('preemptAtSafePoint ignores requests the filter excludes', () async {
      final fake = FakeLlmProvider(
          scriptedWords: List.filled(20, 'w'),
          perToken: const Duration(milliseconds: 20));
      final bloc = LlmBloc.withConfig(LlmConfig(provider: fake));
      await settle();
      fake.loaded = true;

      unawaited(bloc.beginGeneration(
          LlmRequest(requestId: 'read:now', messages: const []),
          onChunk: (_) {}));
      await settle(1); // let the queue start it
      final freed = await bloc.preemptAtSafePoint(
          where: (id) => id.startsWith('well-'));
      expect(freed, isFalse);
      expect(bloc.activeRequestId, 'read:now');
    });
  });

  group('the wedge (0.4.0) — a hung teardown fails fast, never silently', () {
    LlmBloc wedgedBloc(FakeLlmProvider provider) =>
        LlmBloc.withConfig(LlmConfig(
          provider: provider,
          teardownPatience: const Duration(milliseconds: 120),
        ));

    test('teardown past the ceiling declares the wedge; new work refuses',
        () async {
      final provider = WedgedProvider();
      final bloc = wedgedBloc(provider);
      await ready(bloc);

      final gen = bloc.beginGeneration(
          const LlmRequest(requestId: 'well-1', messages: []),
          onChunk: (_) {});
      await provider.started.future;
      expect(bloc.engineWedged, isFalse);

      // The caller is released immediately (0.3.0 contract)…
      await bloc.stopGeneration();
      expect((await gen).kind, GenOutcomeKind.cancelled);

      // …and past the teardown ceiling the engine is declared wedged.
      await settle(300);
      expect(bloc.engineWedged, isTrue);

      // New generations fail FAST with a loud error — no queue wait.
      final refused = await bloc.beginGeneration(
          const LlmRequest(requestId: 'chat-1', messages: []),
          onChunk: (_) {});
      expect(refused.kind, GenOutcomeKind.error);
      expect('${refused.error}', contains('wedged'));

      // The lease refuses immediately rather than starving its caller.
      await expectLater(bloc.acquireEngine(), throwsStateError);

      // Nothing preemptible on a wedged engine — callers proceed to their
      // own fast failure.
      expect(await bloc.preemptAtSafePoint(), isTrue);
    });

    test('the incident replay: work arriving DURING the hung teardown '
        'fails fast once the ceiling passes', () async {
      // 2026-08-01, from the engine journal: stop at 11:16 (teardown never
      // returned), a tag re-queue at 11:32 and a colloquy lease at 11:32:54
      // then waited forever against an empty engine. This is that tape,
      // with the 0.4.0 ending.
      final provider = WedgedProvider();
      final bloc = wedgedBloc(provider);
      await ready(bloc);

      final gen = bloc.beginGeneration(
          const LlmRequest(requestId: 'well-1', messages: []),
          onChunk: (_) {});
      await provider.started.future;
      await bloc.stopGeneration();
      await gen;

      // While the teardown hangs (ceiling not yet passed), work arrives —
      // exactly the 11:32 re-queue and lease-wait.
      final queued = bloc.beginGeneration(
          const LlmRequest(requestId: 'well-2', messages: []),
          onChunk: (_) {});
      // The expectation attaches NOW — the rejection fires at the ceiling,
      // and an unlistened error would kill the test zone.
      final lease = expectLater(bloc.acquireEngine(), throwsStateError);

      await settle(300); // ceiling passes → wedge declared → both settle

      final outcome = await queued;
      expect(outcome.kind, GenOutcomeKind.error,
          reason: 'queued work must fail, not wait forever');
      expect('${outcome.error}', contains('wedged'));
      await lease;
      expect(bloc.engineWedged, isTrue);
    });

    test('a LATE teardown lifts the wedge — the runtime recovered (0.4.1)',
        () async {
      // 2026-08-08, from a field log: a mid-prefill stop wedged the engine,
      // then its teardown returned 89s later. The native runtime had
      // recovered — but the sticky flag kept a healthy engine condemned
      // until app restart. A wedge is a claim ("this call never returns");
      // the late return falsifies it.
      final provider = LateTeardownProvider();
      final bloc = wedgedBloc(provider);
      await ready(bloc);

      final gen = bloc.beginGeneration(
          const LlmRequest(requestId: 'well-37', messages: []),
          onChunk: (_) {});
      await provider.started.future;
      await bloc.stopGeneration();
      await gen;

      // Ceiling passes with the teardown still stuck → wedged, refusing.
      await settle(300);
      expect(bloc.engineWedged, isTrue);
      final refused = await bloc.beginGeneration(
          const LlmRequest(requestId: 'well-38', messages: []),
          onChunk: (_) {});
      expect('${refused.error}', contains('wedged'));

      // The stuck native call finally returns (89s in the field, ms here).
      provider.release.complete();
      await settle();
      expect(bloc.engineWedged, isFalse,
          reason: 'the late teardown falsifies the wedge claim');

      // And the engine genuinely serves again.
      final again = await bloc.beginGeneration(
          const LlmRequest(requestId: 'well-39', messages: []),
          onChunk: (_) {});
      expect(again.kind, isNot(GenOutcomeKind.error),
          reason: 'an un-wedged engine must accept new work');
    });
  });
}
