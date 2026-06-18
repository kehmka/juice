import 'package:juice_llm/juice_llm.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart' as lcpp;

/// Builds a raw prompt string from chat messages. Use this for models whose
/// embedded chat template llama.cpp can't apply — e.g. Gemma 4, whose template
/// is tool-use Jinja the runtime can't parse. When a [ChatFormat] is set on
/// [LlamaCppProvider], generation renders the prompt here and uses the raw
/// session path instead of the model's chat template.
///
/// **Multimodal:** a message's [LlmMessage.images] / [LlmMessage.audio] become
/// one media marker (`<__media__>`) each, prepended to that turn's content in
/// order (images, then audio). The marker order MUST match the order the
/// provider hands the bytes to llama.cpp — both iterate the non-system
/// messages in sequence — so mtmd splices the right embedding at each marker.
typedef ChatFormat = String Function(List<LlmMessage> messages);

/// The marker mtmd substitutes with one media item's embeddings, in order.
const String kMediaMarker = '<__media__>';

/// Gemma family format: `<start_of_turn>user … <end_of_turn>` /
/// `<start_of_turn>model`. Gemma has no `system` role, so system text is folded
/// into the first user turn. Media markers are injected per turn (see
/// [ChatFormat]). Verified end-to-end with Gemma 4 E2B (text + vision).
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
    final markerCount = m.images.length + m.audio.length;
    if (markerCount > 0) {
      final markers = List<String>.filled(markerCount, kMediaMarker).join('\n');
      content = content.isEmpty ? markers : '$markers\n$content';
    }
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
/// **Multimodal:** pass [LlmLoadOptions.projectorPath] (an mmproj GGUF) to
/// [load] and the engine loads the vision/audio encoder. Requests then carry
/// images/audio in their messages ([LlmMessage.images] / [LlmMessage.audio]);
/// the provider splices them at the media markers. When the projector loads,
/// [capabilities] gains `vision` + `audio` (honest: it reflects what actually
/// loaded, not what was hoped). A request with media but no projector loaded
/// fails loud.
///
/// Each [generate] is a stateless one-shot (the session/chat is reset per
/// request). Generation is one-at-a-time (the engine is single-active),
/// matching `LlmBloc`'s `sequential` generate queue.
///
/// **Cancellation:** cancelling the returned stream cancels the generation. On
/// the published `llama_cpp_dart` 0.9.0-dev.9 this is *soft* (delivery stops,
/// the worker finishes the current decode). True mid-decode interrupt arrives
/// with netdur/llama_cpp_dart#106; no change needed here.
///
/// **Known caveat:** on Metal, llama.cpp currently raises a teardown assertion
/// (`ggml-metal-device.m` `GGML_ASSERT([rsets->data count] == 0)`) during
/// process finalization *after* a multimodal run completes — generation output
/// is unaffected. Tracked upstream (ggml-org/llama.cpp#17869). Keep the engine
/// loaded for the app's lifetime (we do) so dispose-at-exit is rare.
class LlamaCppProvider implements LlmProvider {
  LlamaCppProvider({
    this.libraryPath,
    this.useProcessSymbols = false,
    this.chatFormat,
    Set<LlmCapability> capabilities = const {
      LlmCapability.text,
      LlmCapability.embeddings,
    },
  })  : _declaredCapabilities = capabilities,
        assert(libraryPath != null || useProcessSymbols,
            'pass libraryPath (dev/CLI) or set useProcessSymbols (app xcframework)');

  /// Path to `libllama.dylib` (+ siblings). Required unless [useProcessSymbols].
  final String? libraryPath;

  /// Resolve symbols from the running process (an embedded xcframework) instead
  /// of a dylib path — the iOS / macOS-app path.
  final bool useProcessSymbols;

  /// Build the prompt manually instead of using the model's embedded chat
  /// template. Required for models llama.cpp can't template (Gemma 4).
  final ChatFormat? chatFormat;

  final Set<LlmCapability> _declaredCapabilities;

  /// What the provider can do. Augmented with `vision` + `audio` once a
  /// multimodal projector has actually loaded — capability reflects reality,
  /// never an unbacked promise.
  @override
  Set<LlmCapability> get capabilities => _engine?.multimodalLoaded == true
      ? {..._declaredCapabilities, LlmCapability.vision, LlmCapability.audio}
      : _declaredCapabilities;

  lcpp.LlamaEngine? _engine;
  lcpp.EngineChat? _chat;
  lcpp.EngineSession? _session;

  @override
  String get name => 'llama_cpp';

  bool get _multimodalLoaded => _engine?.multimodalLoaded == true;

  @override
  Future<void> load(String modelPath, LlmLoadOptions options) async {
    if (_engine != null) await unload();
    try {
      final modelParams =
          lcpp.ModelParams(path: modelPath, gpuLayers: options.gpuLayers);
      final contextParams =
          lcpp.ContextParams(nCtx: options.contextTokens, nSeqMax: 1);
      final multimodal = options.projectorPath == null
          ? null
          : lcpp.MultimodalParams(
              mmprojPath: options.projectorPath!,
              useGpu: options.gpuLayers > 0,
            );
      _engine = useProcessSymbols
          ? await lcpp.LlamaEngine.spawnFromProcess(
              modelParams: modelParams,
              contextParams: contextParams,
              multimodalParams: multimodal)
          : await lcpp.LlamaEngine.spawn(
              libraryPath: libraryPath!,
              modelParams: modelParams,
              contextParams: contextParams,
              multimodalParams: multimodal);
      // Fail loud: a requested projector that didn't load is a silent
      // downgrade to text-only — never let it pass.
      if (multimodal != null && !_engine!.multimodalLoaded) {
        throw LlmProviderException(
            'multimodal projector failed to load: ${options.projectorPath}');
      }
      if (chatFormat != null) {
        _session = await _engine!.createSession();
      } else {
        _chat = await _engine!.createChat();
      }
    } catch (e) {
      await _engine?.dispose();
      _engine = null;
      _chat = null;
      _session = null;
      if (e is LlmProviderException) rethrow;
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
    final media = _collectMedia(request.messages);
    if (media.isNotEmpty && !_multimodalLoaded) {
      throw const LlmProviderException(
          'request carries media but no multimodal projector is loaded '
          '(pass LlmLoadOptions.projectorPath)');
    }
    final p = request.params;
    final sampler =
        lcpp.SamplerParams(temperature: p.temperature, topP: p.topP);
    final maxTokens = p.maxTokens ?? 512;

    final Stream<lcpp.GenerationEvent> stream;
    if (chatFormat != null) {
      // Manual prompt path (Gemma 4 etc.). Reset the session's KV each call.
      // The prompt's markers (injected by chatFormat) align with [media] —
      // both walk the non-system messages in order, images before audio.
      await _session!.clear();
      stream = _session!.generate(
        prompt: chatFormat!(request.messages),
        addSpecial: true,
        media: media,
        sampler: sampler,
        maxTokens: maxTokens,
      );
    } else {
      // Embedded-template path. Reset history so each request is one-shot.
      // addUser auto-prepends one marker per media item.
      _chat!.clearHistory();
      for (final m in request.messages) {
        switch (m.role) {
          case LlmRole.system:
            _chat!.addSystem(m.content);
          case LlmRole.user:
            _chat!.addUser(m.content, media: _mediaOf(m));
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

  /// Media from one message, images before audio (marker order).
  static List<lcpp.LlamaMedia> _mediaOf(LlmMessage m) => [
        for (final img in m.images) lcpp.LlamaMedia.imageBytes(img),
        for (final aud in m.audio) lcpp.LlamaMedia.audioBytes(aud),
      ];

  /// All media across the non-system turns, in the order their markers appear
  /// (matching [gemmaChatFormat]'s injection).
  static List<lcpp.LlamaMedia> _collectMedia(List<LlmMessage> messages) => [
        for (final m in messages.where((m) => m.role != LlmRole.system))
          ..._mediaOf(m),
      ];

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
