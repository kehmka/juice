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

  /// Streaming-emission throttle: at most one state emission per session per
  /// this interval (a final unthrottled emission always lands on terminal
  /// status). Guards the rebuild pipeline against token-rate emissions.
  final Duration streamThrottle;

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
    this.maxRetainedSessions = 8,
  }) : provider = provider ?? EchoLlmProvider();
}
