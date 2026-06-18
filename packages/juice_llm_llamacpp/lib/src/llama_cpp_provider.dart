import 'package:juice_llm/juice_llm.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart' as lcpp;

/// An [LlmProvider] backed by **llama.cpp** (GGUF weights, Metal/CPU) through
/// `llama_cpp_dart`'s off-isolate `LlamaEngine` — embedded, in-process, private.
///
/// Provisioning the native library is `llama_cpp_dart`'s concern:
/// - **macOS dev / CLI:** pass [libraryPath] to a downloaded `libllama.dylib`.
/// - **iOS / macOS app:** embed `llama.xcframework` (Embed & Sign) and set
///   [useProcessSymbols] = true — no path needed (dyld resolves it).
///
/// One reusable chat is kept and its history cleared per request, so each
/// [generate] is a stateless one-shot (the worker also clears the KV cache on
/// every chat generate). Generation is one-at-a-time (the engine is
/// single-active), matching `LlmBloc`'s `sequential` generate queue.
///
/// **Cancellation:** cancelling the returned stream cancels the underlying
/// generation. On the published `llama_cpp_dart` 0.9.0-dev.9 this is *soft* —
/// delivery stops but the worker finishes the current generation (fine for the
/// short reflections the Almanac generates). True mid-decode interrupt arrives
/// when netdur/llama_cpp_dart#106 lands; no change needed here.
class LlamaCppProvider implements LlmProvider {
  LlamaCppProvider({
    this.libraryPath,
    this.useProcessSymbols = false,
    this.capabilities = const {LlmCapability.text, LlmCapability.embeddings},
  }) : assert(libraryPath != null || useProcessSymbols,
            'pass libraryPath (dev/CLI) or set useProcessSymbols (app xcframework)');

  /// Path to `libllama.dylib` (+ siblings). Required unless [useProcessSymbols].
  final String? libraryPath;

  /// Resolve symbols from the running process (an embedded xcframework) instead
  /// of a dylib path — the iOS / macOS-app path.
  final bool useProcessSymbols;

  @override
  final Set<LlmCapability> capabilities;

  lcpp.LlamaEngine? _engine;
  lcpp.EngineChat? _chat;

  @override
  String get name => 'llama_cpp';

  @override
  Future<void> load(String modelPath, LlmLoadOptions options) async {
    if (_engine != null) await unload();
    try {
      final modelParams =
          lcpp.ModelParams(path: modelPath, gpuLayers: options.gpuLayers);
      final contextParams =
          lcpp.ContextParams(nCtx: options.contextTokens, nSeqMax: 1);
      _engine = useProcessSymbols
          ? await lcpp.LlamaEngine.spawnFromProcess(
              modelParams: modelParams, contextParams: contextParams)
          : await lcpp.LlamaEngine.spawn(
              libraryPath: libraryPath!,
              modelParams: modelParams,
              contextParams: contextParams);
      _chat = await _engine!.createChat();
    } catch (e) {
      _engine = null;
      _chat = null;
      throw LlmProviderException('llama.cpp load failed', cause: e);
    }
  }

  @override
  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    _chat = null;
    await engine?.dispose();
  }

  @override
  Stream<LlmChunk> generate(LlmRequest request) async* {
    final chat = _chat;
    if (chat == null) {
      throw const LlmProviderException('generate() with no model loaded');
    }
    // Stateless one-shot: drop prior turns, render only this request.
    chat.clearHistory();
    for (final m in request.messages) {
      switch (m.role) {
        case LlmRole.system:
          chat.addSystem(m.content);
        case LlmRole.user:
          chat.addUser(m.content);
        case LlmRole.assistant:
          chat.addAssistant(m.content);
      }
    }

    final p = request.params;
    final stream = chat.generate(
      sampler: lcpp.SamplerParams(temperature: p.temperature, topP: p.topP),
      maxTokens: p.maxTokens ?? 512,
    );
    // Cancelling the consumer cancels this await-for → cancels chat.generate.
    await for (final event in stream) {
      if (event is lcpp.TokenEvent) {
        if (event.text.isNotEmpty) yield LlmChunk(event.text, tokens: 1);
      } else if (event is lcpp.DoneEvent) {
        yield LlmChunk(event.trailingText, done: true);
      }
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    if (!capabilities.contains(LlmCapability.embeddings)) {
      throw UnsupportedError('embeddings disabled for this provider');
    }
    final engine = _engine;
    if (engine == null) {
      throw const LlmProviderException('embed() with no model loaded');
    }
    final result = await engine.embed(text);
    return result.vector.toList();
  }

  @override
  Future<void> dispose() async => unload();
}
