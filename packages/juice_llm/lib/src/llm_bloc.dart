import 'dart:async';

import 'package:juice/juice.dart';

import 'llm_config.dart';
import 'llm_events.dart';
import 'llm_model.dart';
import 'llm_provider.dart';
import 'llm_request.dart';
import 'llm_state.dart';
import 'model_source.dart';
import 'use_cases/cancel_generation_use_case.dart';
import 'use_cases/embed_use_case.dart';
import 'use_cases/evict_session_use_case.dart';
import 'use_cases/fetch_model_use_case.dart';
import 'use_cases/generate_use_case.dart';
import 'use_cases/initialize_llm_use_case.dart';
import 'use_cases/load_model_use_case.dart';
import 'use_cases/unload_model_use_case.dart';

/// How a generation stream ended (see [LlmBloc.beginGeneration]).
enum GenOutcomeKind { done, cancelled, error }

/// The terminal result of a generation stream.
class GenerationOutcome {
  final GenOutcomeKind kind;
  final Object? error;
  const GenerationOutcome(this.kind, {this.error});
}

/// On-device LLM inference as a bloc: a model-lifecycle state machine
/// (absent → fetching → fetched → loading → ready) plus streaming generation
/// and embedding **sessions**, behind a swappable [LlmProvider] runtime seam
/// and a [ModelSource] acquisition seam.
///
/// Token streaming arrives as state emissions on a per-request group
/// (`llm:gen:<requestId>`), throttled so the rebuild pipeline never sees
/// token-rate churn (a final unthrottled emission always lands on terminal
/// status). One generation runs at a time (`GenerateEvent` is `sequential`);
/// cancellation runs *concurrently* and stops the runtime out-of-band.
///
/// ```dart
/// final llm = LlmBloc.withConfig(LlmConfig()); // Echo runtime, no downloads
/// llm.generate(LlmRequest(requestId: 'r1', messages: [LlmMessage.user('hi')]));
/// // a widget binds LlmGroups.gen('r1') and reads session.text as it streams
/// ```
class LlmBloc extends JuiceBloc<LlmState> {
  late LlmConfig _config;

  /// The in-flight generation's stream subscription, if any. Cancelling it
  /// stops the provider's runtime (out-of-band) — that's how
  /// [CancelGenerationEvent] works.
  StreamSubscription<LlmChunk>? _genSub;

  /// requestId of the generation currently streaming (for the cancel path).
  String? _activeRequestId;

  /// Throttle bookkeeping for streamed emissions. Only one generation streams
  /// at a time (`GenerateEvent` is `sequential`), so a single timer + pending
  /// closure suffices.
  Timer? _throttleTimer;
  void Function()? _pendingEmit;

  LlmBloc()
      : super(
          LlmState.initial,
          [
            () => UseCaseBuilder(
                typeOfEvent: InitializeLlmEvent,
                useCaseGenerator: () => InitializeLlmUseCase()),
            // droppable: a second fetch tap while one runs is redundant.
            () => UseCaseBuilder(
                typeOfEvent: FetchModelEvent,
                useCaseGenerator: () => FetchModelUseCase(),
                concurrency: EventConcurrency.droppable),
            // sequential: load/unload mutate the runtime; serialize them.
            () => UseCaseBuilder(
                typeOfEvent: LoadModelEvent,
                useCaseGenerator: () => LoadModelUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: UnloadModelEvent,
                useCaseGenerator: () => UnloadModelUseCase(),
                concurrency: EventConcurrency.sequential),
            // sequential: one runtime context ⇒ generations queue in order.
            () => UseCaseBuilder(
                typeOfEvent: GenerateEvent,
                useCaseGenerator: () => GenerateUseCase(),
                concurrency: EventConcurrency.sequential),
            // concurrent: cancel must run *during* a generate to stop it.
            () => UseCaseBuilder(
                typeOfEvent: CancelGenerationEvent,
                useCaseGenerator: () => CancelGenerationUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: EmbedEvent,
                useCaseGenerator: () => EmbedUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: EvictSessionEvent,
                useCaseGenerator: () => EvictSessionUseCase()),
          ],
        );

  /// Create and initialize in one step.
  factory LlmBloc.withConfig(LlmConfig config) {
    final bloc = LlmBloc();
    bloc.send(InitializeLlmEvent(config: config));
    return bloc;
  }

  // === Config (used by use cases) ===

  void configure(LlmConfig config) => _config = config;
  LlmConfig get config => _config;
  LlmProvider get provider => _config.provider;
  ModelSource? get modelSource => _config.modelSource;

  // === Generation lifecycle (resources live here) ===

  Completer<GenerationOutcome>? _genOutcome;

  /// requestId of the generation currently streaming, or null.
  String? get activeRequestId => _activeRequestId;

  /// One compact line to the configured engine trace (no-op when unset).
  void _trace(String event) => _config.onEngineTrace?.call(event);
  bool get isGenerating => _activeRequestId != null;

  /// Begin streaming [request] through the provider, forwarding each chunk to
  /// [onChunk]. Returns a future that completes **once**, however the stream
  /// ends — naturally ([GenOutcomeKind.done]), with an error
  /// ([GenOutcomeKind.error]), or via [stopGeneration]
  /// ([GenOutcomeKind.cancelled]). One finalize point ⇒ no double-finalize
  /// race, and the `sequential` queue is never wedged (cancelling a
  /// subscription does *not* fire `onDone`, so the cancel path completes it).
  ///
  /// SERIALIZED at the resource: one runtime context ⇒ one stream at a time,
  /// no matter who calls. `GenerateEvent` already queues, but service-layer
  /// callers await this method directly — two of those used to race straight
  /// into the provider (fine while nothing generated in the background;
  /// constant collisions once a phone enriches its well continuously,
  /// 2026-07-14). A call made mid-generation now waits its turn.
  Future<GenerationOutcome> beginGeneration(
    LlmRequest request, {
    required void Function(LlmChunk) onChunk,
  }) {
    // Wedged → fail NOW, not after an infinite queue wait. Checked again
    // inside the chain for work that was already queued when the wedge was
    // declared — it must not touch the stuck runtime either.
    if (_wedged) {
      _trace('refused ${request.requestId} (engine wedged)');
      return Future.value(_wedgedOutcome);
    }
    _trace('queue ${request.requestId} '
        '(active=${_activeRequestId ?? '-'} leased=$engineLeased)');
    final next = _genTail.then<GenerationOutcome>((_) {
      if (_wedged) {
        _trace('refused ${request.requestId} (engine wedged, was queued)');
        return _wedgedOutcome;
      }
      return _startGeneration(request, onChunk: onChunk);
    });
    // The outcome future never throws (errors arrive as GenOutcomeKind.error),
    // but keep the chain unbreakable regardless.
    _genTail = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// The tail of the generation queue — each [beginGeneration] chains here.
  Future<void> _genTail = Future<void>.value();

  /// The runtime is WEDGED: a stopped generation's teardown never returned
  /// within [LlmConfig.teardownPatience] — a native thread is stuck
  /// mid-call and no in-process remedy exists. Once true, every queued and
  /// future generation fails fast, [acquireEngine] throws, and the only
  /// recovery is an app restart. Loud by construction: the alternative was
  /// the poisoned queue, where everything waited forever in silence.
  bool get engineWedged => _wedged;
  bool _wedged = false;

  void _declareWedged(String? id) {
    if (_wedged) return;
    _wedged = true;
    _trace('wedged ${id ?? '-'} — teardown never returned '
        '(${_config.teardownPatience.inSeconds}s); the native runtime is '
        'stuck mid-call. Restart required; all engine work now fails fast.');
  }

  /// The outcome every generation receives once the engine is wedged.
  static const _wedgedOutcome = GenerationOutcome(GenOutcomeKind.error,
      error: 'engine wedged — restart required');

  /// The ENGINE LEASE — exclusive ownership of the runtime for a caller that
  /// holds a session ACROSS turns (a tool-loop conversation). The native
  /// runtimes hold ONE live session per model, so any generation that starts
  /// between a conversation's turns destroys the conversation's session
  /// ("Bad state: Session is closed"). While a lease is held,
  /// [beginGeneration] queues behind [EngineLease.release] instead of
  /// touching the runtime. Serialization alone cannot provide this — the
  /// queue is turn-grained; the lease is lifetime-grained.
  Completer<void>? _lease;

  /// Whether an [EngineLease] is currently held.
  bool get engineLeased => _lease != null && !_lease!.isCompleted;

  /// Acquire exclusive engine ownership: waits for the in-flight generation
  /// (and any earlier lease) to finish, then holds the runtime until
  /// [EngineLease.release]. The holder drives the runtime OUTSIDE
  /// [beginGeneration] (e.g. flutter_gemma's chat lane); everyone else's
  /// generations queue. ALWAYS release in a finally — an unreleased lease
  /// starves every other caller, loudly visible via [engineLeased].
  Future<EngineLease> acquireEngine() async {
    if (_wedged) {
      _trace('lease-refused (engine wedged)');
      throw StateError('engine wedged — restart required');
    }
    // Chain onto the queue so acquisition respects in-flight + queued work,
    // and subsequent generations chain behind our release.
    _trace('lease-wait (active=${_activeRequestId ?? '-'})');
    final acquired = Completer<void>();
    final release = Completer<void>();
    _genTail = _genTail.then((_) {
      if (_wedged) {
        _trace('lease-refused (engine wedged, was queued)');
        acquired.completeError(
            StateError('engine wedged — restart required'));
        return Future<void>.value();
      }
      _lease = release;
      _trace('lease-held');
      acquired.complete();
      return release.future;
    });
    await acquired.future;
    return EngineLease._(() {
      if (!release.isCompleted) {
        _lease = null;
        _trace('lease-released');
        release.complete();
      }
    });
  }

  Future<GenerationOutcome> _startGeneration(
    LlmRequest request, {
    required void Function(LlmChunk) onChunk,
  }) {
    _activeRequestId = request.requestId;
    _trace('start ${request.requestId}');
    final startedAt = DateTime.now();
    int ms() => DateTime.now().difference(startedAt).inMilliseconds;
    var tokens = 0;
    final outcome = Completer<GenerationOutcome>();
    _genOutcome = outcome;
    _activeStreamed = false;
    final firstChunk = Completer<void>();
    _firstChunk = firstChunk;
    void settleFirstChunk() {
      if (!firstChunk.isCompleted) firstChunk.complete();
    }

    _genSub = provider.generate(request).listen(
      (c) {
        // The first chunk marks the end of PREFILL — the runtime is now
        // decoding, where cancellation is prompt and safe. The safe-point
        // preempt ([preemptAtSafePoint]) waits on exactly this edge.
        if (!_activeStreamed) {
          _activeStreamed = true;
          _trace('first-chunk ${request.requestId} +${ms()}ms');
          settleFirstChunk();
        }
        tokens++;
        onChunk(c);
      },
      onDone: () {
        _genSub = null;
        _activeRequestId = null;
        _cancelThrottle();
        settleFirstChunk();
        _trace('done ${request.requestId} +${ms()}ms ${tokens}tok');
        if (!outcome.isCompleted) {
          outcome.complete(const GenerationOutcome(GenOutcomeKind.done));
        }
      },
      onError: (Object e) {
        _genSub = null;
        _activeRequestId = null;
        _cancelThrottle();
        settleFirstChunk();
        _trace('error ${request.requestId} +${ms()}ms ${tokens}tok: $e');
        if (!outcome.isCompleted) {
          outcome.complete(GenerationOutcome(GenOutcomeKind.error, error: e));
        }
      },
      cancelOnError: true,
    );
    return outcome.future;
  }

  /// True once the ACTIVE generation has streamed at least one chunk —
  /// prefill is over, the runtime is decoding: the safe-cancel window.
  bool _activeStreamed = false;

  /// Completes at the active generation's first chunk (or its end, so no
  /// waiter ever hangs on a zero-chunk outcome).
  Completer<void>? _firstChunk;

  /// Preempt the active generation at the next SAFE point.
  ///
  /// Cancelling a provider mid-PREFILL can wedge the native runtime (LiteRT
  /// wedged on exactly this, Amoli 2026-07-26) — and a wedged generator can
  /// never reach the yield boundary a cancel needs, so the old blind
  /// stop-then-generate pattern hung its caller forever (the Read button,
  /// 2026-07-29). Once tokens stream, every chunk is a yield boundary and
  /// cancellation is prompt.
  ///
  /// So: already decoding → cancel now. Still prefilling → wait for the
  /// first chunk (the prefill's own duration bounds the wait), then cancel.
  /// No chunk within [patience] → leave it to run and return false (the
  /// caller queues; its own watchdog stays the loud ceiling). [where]
  /// filters which requests may be preempted — e.g. only background
  /// `'well-'` reads. Returns true when the engine was freed (cancelled or
  /// ended on its own).
  Future<bool> preemptAtSafePoint({
    bool Function(String requestId)? where,
    Duration patience = const Duration(seconds: 45),
  }) async {
    // A wedged engine holds nothing preemptible — return true so the
    // caller proceeds straight to its beginGeneration, which fails fast.
    if (_wedged) return true;
    final id = _activeRequestId;
    if (id == null) return true;
    if (where != null && !where(id)) return false;
    _trace('preempt-wait $id (streamed=$_activeStreamed)');
    if (!_activeStreamed) {
      final first = _firstChunk?.future;
      if (first != null) {
        final streamed = await Future.any<bool>([
          first.then((_) => true),
          Future<bool>.delayed(patience, () => false),
        ]);
        if (!streamed) return false;
      }
    }
    if (_activeRequestId != id) return true; // ended on its own
    await stopGeneration();
    return true;
  }

  /// Stop the in-flight generation: cancels the provider stream (runtime stops
  /// decoding) and completes its outcome as `cancelled`. Returns the stopped
  /// requestId, or null if nothing was streaming.
  Future<String?> stopGeneration() async {
    final id = _activeRequestId;
    final sub = _genSub;
    final outcome = _genOutcome;
    _genSub = null;
    _activeRequestId = null;
    _genOutcome = null;
    _cancelThrottle();
    // The CALLER must never block on the provider's teardown: an async*
    // generator cancel only completes at a yield boundary, and a runtime
    // wedged mid-native-call has none — `await sub.cancel()` here hung a
    // caller FOREVER, outside every watchdog (Amoli's Read button,
    // 2026-07-29). The QUEUE still waits: one live session per model means
    // the next generation may not touch the provider until teardown truly
    // finishes — so the teardown chains onto [_genTail] instead, and queued
    // work behind a wedged teardown surfaces through its callers' own
    // watchdogs, loudly, rather than as a silent hang here.
    _trace('stop ${id ?? '-'} (streamed=$_activeStreamed)');
    if (sub != null) {
      final stopAt = DateTime.now();
      final teardown = sub.cancel().then((_) {
        _trace('teardown ${id ?? '-'} '
            '+${DateTime.now().difference(stopAt).inMilliseconds}ms'
            '${_wedged ? ' (late — after wedge declaration)' : ''}');
      });
      // THE TEARDOWN CEILING (0.4.0): a cancel with no yield boundary never
      // returns; past the ceiling the engine is declared wedged and the
      // queue tail RESOLVES so everything behind it can fail fast instead
      // of waiting forever (the poisoned queue, 2026-08-01).
      _genTail = _genTail
          .then((_) => teardown.timeout(_config.teardownPatience, onTimeout: () {
                _declareWedged(id);
              }))
          .then((_) {}, onError: (_) {});
    }
    if (outcome != null && !outcome.isCompleted) {
      outcome.complete(const GenerationOutcome(GenOutcomeKind.cancelled));
    }
    return id;
  }

  // === Streamed-emission throttle (leading + trailing) ===
  //
  // Coalesce token chunks to at most one emission per `config.streamThrottle`:
  // the first chunk emits immediately (leading), chunks within the window
  // overwrite a single pending closure (latest text wins), and the timer
  // flushes that pending closure when the window closes (trailing). The
  // terminal chunk goes through [flushStreamEmit] (unthrottled). The use case
  // calls [scheduleStreamEmit] per chunk with a closure that captures that
  // chunk's accumulated text — so a coalesced/dropped chunk never loses text.

  void scheduleStreamEmit(void Function() emit) {
    if (_throttleTimer?.isActive ?? false) {
      _pendingEmit = emit; // latest wins; flushed when the window closes
      return;
    }
    if (!isClosed) emit(); // leading edge
    _pendingEmit = null;
    _throttleTimer = Timer(_config.streamThrottle, () {
      final pending = _pendingEmit;
      _pendingEmit = null;
      _throttleTimer = null;
      if (pending != null && !isClosed) pending();
    });
  }

  /// Force an immediate emission (terminal chunk) and reset the throttle.
  void flushStreamEmit(void Function() emit) {
    _cancelThrottle();
    if (!isClosed) emit();
  }

  void _cancelThrottle() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _pendingEmit = null;
  }

  // === Session helpers (used by use cases) ===

  GenerationSession? session(String requestId) => state.sessions[requestId];

  /// Replace one session; prune retained terminal sessions beyond the cap
  /// (oldest terminal first — active sessions are never pruned).
  Map<String, GenerationSession> upsertSession(GenerationSession s) {
    final next = Map<String, GenerationSession>.from(state.sessions);
    next[s.requestId] = s;
    final terminal =
        next.values.where((x) => x.isTerminal).toList();
    final overflow = terminal.length - _config.maxRetainedSessions;
    if (overflow > 0) {
      for (var i = 0; i < overflow; i++) {
        next.remove(terminal[i].requestId);
      }
    }
    return next;
  }

  Map<String, GenerationSession> removeSession(String requestId) {
    final next = Map<String, GenerationSession>.from(state.sessions);
    next.remove(requestId);
    return next;
  }

  // === Convenience API ===

  void fetchModel(LlmModel model) => send(FetchModelEvent(model));
  void loadModel(LlmModel model) => send(LoadModelEvent(model));
  void unloadModel() => send(UnloadModelEvent());
  void generate(LlmRequest request) => send(GenerateEvent(request));
  void cancel(String requestId) => send(CancelGenerationEvent(requestId));
  void evictSession(String requestId) => send(EvictSessionEvent(requestId));

  /// Compute an embedding (awaits the provider). Throws if the model lacks the
  /// embeddings capability or none is loaded.
  Future<List<double>> embed(String text) {
    final event = EmbedEvent(text);
    send(event);
    return event.result;
  }

  @override
  Future<void> close() async {
    _cancelThrottle();
    await _genSub?.cancel();
    try {
      await _config.provider.dispose();
    } catch (_) {
      // Config may never have been applied; ignore.
    }
    await super.close();
  }
}

/// Exclusive engine ownership — see [LlmBloc.acquireEngine]. Release exactly
/// once, in a finally.
class EngineLease {
  EngineLease._(this._release);
  final void Function() _release;
  var _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}
