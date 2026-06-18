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
}
