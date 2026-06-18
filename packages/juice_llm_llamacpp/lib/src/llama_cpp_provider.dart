import 'package:juice_llm/juice_llm.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart' as lcpp;

/// Builds a raw prompt string from chat messages. Use this for models whose
/// embedded chat template llama.cpp can't apply — e.g. Gemma 4, whose template
/// is tool-use Jinja the runtime can't parse. When a [ChatFormat] is set on
/// [LlamaCppProvider], generation renders the prompt here and uses the raw
/// session path instead of the model's chat template.
typedef ChatFormat = String Function(List<LlmMessage> messages);

/// Gemma family format: `<start_of_turn>user … <end_of_turn>` /
/// `<start_of_turn>model`. Gemma has no `system` role, so system text is folded
/// into the first user turn. Verified end-to-end with Gemma 4 E2B.
String gemmaChatFormat(List<LlmMessage> messages) {
  final system = messages
      .where((m) => m.role == LlmRole.system)
      .map((m) => m.content)
      .join('\n');
  final buf = StringBuffer();
  var first = true;
  for (final m in messages.where((m) => m.role != LlmRole.system)) {
    final role = m.role == LlmRole.assistant ? 'model' : 'user';
    var content = m.content;
    if (first && m.role == LlmRole.user && system.isNotEmpty) {
      content = '$system\n\n$content';
    }
    first = false;
    buf.write('<start_of_turn>$role\n$content<end_of_turn>\n');
  }
  buf.write('<start_of_turn>model\n');
  return buf.toString();
}

/// An [LlmProvider] backed by **llama.cpp** (GGUF weights, Metal/CPU) through
/// `llama_cpp_dart`'s off-isolate `LlamaEngine` — embedded, in-process, private.
///
/// Provisioning the native library is `llama_cpp_dart`'s concern:
/// - **macOS dev / CLI:** pass [libraryPath] to a downloaded `libllama.dylib`.
/// - **iOS / macOS app:** embed `llama.xcframework` (Embed & Sign) and set
///   [useProcessSymbols] = true — no path needed (dyld resolves it).
///
/// **Chat templating:** by default the model's embedded template is applied
/// (works for SmolLM2, Qwen, etc.). For models whose embedded template
/// llama.cpp can't parse (Gemma 4), pass a [chatFormat] (e.g. [gemmaChatFormat])
/// and the prompt is built here instead.
///
/// Each [generate] is a stateless one-shot (the session/chat is reset per
/// request). Generation is one-at-a-time (the engine is single-active),
/// matching `LlmBloc`'s `sequential` generate queue.
///
/// **Cancellation:** cancelling the returned stream cancels the generation. On
/// the published `llama_cpp_dart` 0.9.0-dev.9 this is *soft* (delivery stops,
/// the worker finishes the current decode). True mid-decode interrupt arrives
/// with netdur/llama_cpp_dart#106; no change needed here.
class LlamaCppProvider implements LlmProvider {
  LlamaCppProvider({
    this.libraryPath,
    this.useProcessSymbols = false,
    this.chatFormat,
    this.capabilities = const {LlmCapability.text, LlmCapability.embeddings},
  }) : assert(libraryPath != null || useProcessSymbols,
            'pass libraryPath (dev/CLI) or set useProcessSymbols (app xcframework)');

  /// Path to `libllama.dylib` (+ siblings). Required unless [useProcessSymbols].
  final String? libraryPath;

  /// Resolve symbols from the running process (an embedded xcframework) instead
  /// of a dylib path — the iOS / macOS-app path.
  final bool useProcessSymbols;

  /// Build the prompt manually instead of using the model's embedded chat
  /// template. Required for models llama.cpp can't template (Gemma 4).
  final ChatFormat? chatFormat;

  @override
  final Set<LlmCapability> capabilities;

  lcpp.LlamaEngine? _engine;
  lcpp.EngineChat? _chat;
  lcpp.EngineSession? _session;

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
      if (chatFormat != null) {
        _session = await _engine!.createSession();
      } else {
        _chat = await _engine!.createChat();
      }
    } catch (e) {
      _engine = null;
      _chat = null;
      _session = null;
      throw LlmProviderException('llama.cpp load failed', cause: e);
    }
  }

  @override
  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    _chat = null;
    _session = null;
    await engine?.dispose();
  }

  @override
  Stream<LlmChunk> generate(LlmRequest request) async* {
    if (_engine == null) {
      throw const LlmProviderException('generate() with no model loaded');
    }
    final p = request.params;
    final sampler =
        lcpp.SamplerParams(temperature: p.temperature, topP: p.topP);
    final maxTokens = p.maxTokens ?? 512;

    final Stream<lcpp.GenerationEvent> stream;
    if (chatFormat != null) {
      // Manual prompt path (Gemma 4 etc.). Reset the session's KV each call.
      await _session!.clear();
      stream = _session!.generate(
        prompt: chatFormat!(request.messages),
        addSpecial: true,
        sampler: sampler,
        maxTokens: maxTokens,
      );
    } else {
      // Embedded-template path. Reset history so each request is one-shot.
      _chat!.clearHistory();
      for (final m in request.messages) {
        switch (m.role) {
          case LlmRole.system:
            _chat!.addSystem(m.content);
          case LlmRole.user:
            _chat!.addUser(m.content);
          case LlmRole.assistant:
            _chat!.addAssistant(m.content);
        }
      }
      stream = _chat!.generate(sampler: sampler, maxTokens: maxTokens);
    }

    // Cancelling the consumer cancels this await-for → cancels the generation.
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
