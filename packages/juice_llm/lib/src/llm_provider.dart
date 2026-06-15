import 'dart:async';

import 'llm_exceptions.dart';
import 'llm_model.dart';
import 'llm_request.dart';

/// Options applied when loading weights into the runtime.
class LlmLoadOptions {
  /// How many layers to offload to GPU (Metal/CUDA). 0 = CPU only;
  /// a large value = "as many as fit". Providers clamp to what they support.
  final int gpuLayers;

  /// Context window to allocate, in tokens (≤ the model's max).
  final int contextTokens;

  /// Threads for CPU work; null = provider default.
  final int? threads;

  const LlmLoadOptions({
    this.gpuLayers = 999,
    this.contextTokens = 4096,
    this.threads,
  });
}

/// The runtime seam — the `AuthProvider` pattern for LLM inference.
///
/// Implementations marry a specific runtime (llama.cpp via FFI, an
/// OpenAI-compatible HTTP server like Ollama, Google's MediaPipe LLM Inference,
/// a cloud endpoint); `LlmBloc` depends only on this interface, so the runtime
/// is swappable and the bloc never grows a vendor opinion.
///
/// Contract:
/// - [generate] returns a stream that MUST stop the underlying runtime when its
///   listener cancels — cancellation is out-of-band, not a queued request.
/// - Loud failures throw [LlmProviderException]; the bloc surfaces them and
///   never substitutes a fallback model.
/// - [embed] throws [UnsupportedError] unless `embeddings` is in [capabilities].
abstract class LlmProvider {
  /// Stable name for diagnostics (e.g. `echo`, `ollama`, `llama_cpp`).
  String get name;

  /// What this provider/model can do once loaded.
  Set<LlmCapability> get capabilities;

  /// Load weights at [modelPath] into the runtime. Throws
  /// [LlmProviderException] on OOM / format mismatch.
  Future<void> load(String modelPath, LlmLoadOptions options);

  /// Release the runtime (free weights). Safe to call when not loaded.
  Future<void> unload();

  /// Stream a completion. Honor listener cancellation by stopping decoding.
  Stream<LlmChunk> generate(LlmRequest request);

  /// Embedding vector for [text]. Throws [UnsupportedError] if unsupported.
  Future<List<double>> embed(String text);

  /// Release all resources (the provider is done).
  Future<void> dispose();
}

/// A pure-Dart, dependency-free [LlmProvider] — the runnable default and the
/// reference implementation of the seam contract (the `StaticFlagsSource`
/// analog).
///
/// It doesn't run a real model: it "generates" by streaming a templated reply
/// word-by-word with a configurable per-token delay, which exercises the whole
/// bloc — streaming groups, throttled emission, queue order, and cancellation —
/// on any platform with no native code or downloads. Embeddings are a
/// deterministic hash, enough to wire and test a vector path.
class EchoLlmProvider implements LlmProvider {
  EchoLlmProvider({
    this.perTokenDelay = const Duration(milliseconds: 35),
    this.capabilities = const {LlmCapability.text, LlmCapability.embeddings},
    this.embeddingDimensions = 64,
  });

  /// Delay between streamed words — simulates decode latency.
  final Duration perTokenDelay;

  @override
  final Set<LlmCapability> capabilities;

  final int embeddingDimensions;

  bool _loaded = false;

  @override
  String get name => 'echo';

  @override
  Future<void> load(String modelPath, LlmLoadOptions options) async {
    _loaded = true;
  }

  @override
  Future<void> unload() async {
    _loaded = false;
  }

  @override
  Stream<LlmChunk> generate(LlmRequest request) async* {
    if (!_loaded) {
      throw const LlmProviderExceptionNotLoaded();
    }
    // Echo the last user turn back as a short reflective line, word by word.
    final lastUser = request.messages.lastWhere(
      (m) => m.role == LlmRole.user,
      orElse: () => const LlmMessage.user(''),
    );
    final reply = _reflect(lastUser.content);
    final words = reply.split(' ');
    for (var i = 0; i < words.length; i++) {
      // `async*` cancellation: when the listener cancels, the runtime
      // suspends at this await and the generator stops — out-of-band stop.
      await Future<void>.delayed(perTokenDelay);
      final isLast = i == words.length - 1;
      yield LlmChunk(
        i == 0 ? words[i] : ' ${words[i]}',
        tokens: 1,
        done: isLast,
      );
    }
  }

  String _reflect(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'There is nothing here yet to glean.';
    return 'You noted: "$trimmed". A small thing, gathered and kept.';
  }

  @override
  Future<List<double>> embed(String text) async {
    if (!capabilities.contains(LlmCapability.embeddings)) {
      throw UnsupportedError('echo provider: embeddings disabled');
    }
    // Deterministic pseudo-embedding from a rolling hash — not semantic, but
    // stable per input so a vector path can be wired and tested.
    final v = List<double>.filled(embeddingDimensions, 0);
    var h = 2166136261;
    for (final code in text.codeUnits) {
      h = (h ^ code) * 16777619 & 0xffffffff;
      v[h % embeddingDimensions] += 1.0;
    }
    final norm = v.fold<double>(0, (s, x) => s + x * x);
    final mag = norm == 0 ? 1.0 : (norm).clamp(1e-9, double.infinity);
    return [for (final x in v) x / (mag == 0 ? 1 : mag)];
  }

  @override
  Future<void> dispose() async => _loaded = false;
}

/// Internal: a generate() with no model loaded. A subtype of
/// [LlmProviderException] so the bloc's loud-failure handling catches it.
class LlmProviderExceptionNotLoaded extends LlmProviderException {
  const LlmProviderExceptionNotLoaded()
      : super('generate() called with no model loaded');
}
