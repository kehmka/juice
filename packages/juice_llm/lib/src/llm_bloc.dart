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
  bool get isGenerating => _activeRequestId != null;

  /// Begin streaming [request] through the provider, forwarding each chunk to
  /// [onChunk]. Returns a future that completes **once**, however the stream
  /// ends — naturally ([GenOutcomeKind.done]), with an error
  /// ([GenOutcomeKind.error]), or via [stopGeneration]
  /// ([GenOutcomeKind.cancelled]). One finalize point ⇒ no double-finalize
  /// race, and the `sequential` queue is never wedged (cancelling a
  /// subscription does *not* fire `onDone`, so the cancel path completes it).
  Future<GenerationOutcome> beginGeneration(
    LlmRequest request, {
    required void Function(LlmChunk) onChunk,
  }) {
    _activeRequestId = request.requestId;
    final outcome = Completer<GenerationOutcome>();
    _genOutcome = outcome;
    _genSub = provider.generate(request).listen(
      onChunk,
      onDone: () {
        _genSub = null;
        _activeRequestId = null;
        _cancelThrottle();
        if (!outcome.isCompleted) {
          outcome.complete(const GenerationOutcome(GenOutcomeKind.done));
        }
      },
      onError: (Object e) {
        _genSub = null;
        _activeRequestId = null;
        _cancelThrottle();
        if (!outcome.isCompleted) {
          outcome.complete(GenerationOutcome(GenOutcomeKind.error, error: e));
        }
      },
      cancelOnError: true,
    );
    return outcome.future;
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
    await sub?.cancel();
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
