import 'llm_model.dart';
import 'llm_provider.dart';
import 'model_source.dart';

/// Configures an `LlmBloc`.
class LlmConfig {
  /// The runtime seam. Defaults to [EchoLlmProvider] so the bloc runs with no
  /// native code or downloads (the reference/demo runtime).
  final LlmProvider provider;

  /// The acquisition seam. Defaults to null — set it (e.g. a network source)
  /// to support `fetchModel`; with a model already on disk you can load
  /// without one.
  final ModelSource? modelSource;

  /// Optional model loaded on init (if already present, or after a
  /// [LlmConfig.modelSource] fetch the app triggers). Null = load later.
  final LlmModel? initialModel;

  /// Resolves where a model's weights live on disk. Required only when using a
  /// real [modelSource] / [initialModel]; the Echo default ignores the path.
  final String Function(LlmModel model)? resolvePath;

  /// Options applied on load.
  final LlmLoadOptions loadOptions;

  /// ENGINE TRACE (0.3.0): every engine transition — queue, start, first
  /// chunk, outcome, stop, teardown, lease — as one compact line. Wire it
  /// to an on-device journal so a wedge is diagnosable after the fact
  /// (Amoli's 2026-07-30 hunt: a runtime that wedges "over time" is
  /// invisible without a transition log). Null = silent.
  final void Function(String event)? onEngineTrace;

  /// Streaming-emission throttle: at most one state emission per session per
  /// this interval (a final unthrottled emission always lands on terminal
  /// status). Guards the rebuild pipeline against token-rate emissions.
  final Duration streamThrottle;

  /// How long a stopped generation's provider teardown may take before the
  /// engine is declared WEDGED. A cancel that lands mid-native-call has no
  /// yield boundary to complete at — it never returns, and every queued
  /// generation and lease behind it would wait forever (the poisoned-queue
  /// incident, Amoli 2026-08-01: a wedged tag item's teardown starved the
  /// colloquy, the drain, and a card for 20+ minutes). Past this ceiling
  /// the bloc stops waiting: [LlmBloc.engineWedged] flips, and everything
  /// queued or arriving fails FAST and LOUD instead of hanging. 8s is an
  /// eternity for a healthy cancel (they run in milliseconds).
  final Duration teardownPatience;

  /// Most-recent terminal sessions retained in state before old ones are
  /// auto-evicted. Consumers can also evict explicitly.
  final int maxRetainedSessions;

  LlmConfig({
    LlmProvider? provider,
    this.modelSource,
    this.initialModel,
    this.resolvePath,
    this.loadOptions = const LlmLoadOptions(),
    this.streamThrottle = const Duration(milliseconds: 50),
    this.teardownPatience = const Duration(seconds: 8),
    this.maxRetainedSessions = 8,
    this.onEngineTrace,
  }) : provider = provider ?? EchoLlmProvider();
}
