import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:juice_llm/juice_llm.dart';

/// A real [LlmProvider] over a local **Ollama** server (or any compatible
/// runtime at the same endpoints) — the seam-swap reference for juice_llm.
///
/// This is how you run a genuine on-device model today without any FFI:
///
/// ```sh
/// brew install ollama && ollama serve
/// ollama pull gemma3:1b        # or a Gemma 4 tag when present locally
/// ```
///
/// then construct the bloc with this provider instead of the Echo default:
///
/// ```dart
/// LlmBloc.withConfig(LlmConfig(provider: OllamaLlmProvider(model: 'gemma3:1b')));
/// ```
///
/// Streaming: Ollama's `/api/chat` returns newline-delimited JSON; each line
/// carries a `message.content` delta and a `done` flag. Cancellation closes
/// the HTTP client, which aborts the in-flight response (the bloc cancels the
/// generate stream → this generator's `finally` runs → client closes).
class OllamaLlmProvider implements LlmProvider {
  OllamaLlmProvider({
    this.model = 'gemma3:1b',
    Uri? baseUrl,
    this.capabilities = const {LlmCapability.text, LlmCapability.embeddings},
  }) : baseUrl = baseUrl ?? Uri.parse('http://localhost:11434');

  final String model;
  final Uri baseUrl;

  @override
  final Set<LlmCapability> capabilities;

  @override
  String get name => 'ollama';

  // Ollama loads models server-side on first use; nothing to load in-process.
  @override
  Future<void> load(String modelPath, LlmLoadOptions options) async {}

  @override
  Future<void> unload() async {}

  @override
  Stream<LlmChunk> generate(LlmRequest request) async* {
    final client = http.Client();
    try {
      final req = http.Request('POST', baseUrl.resolve('/api/chat'))
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({
          'model': model,
          'stream': true,
          'messages': [
            for (final m in request.messages)
              {'role': m.role.name, 'content': m.content},
          ],
          'options': {
            'temperature': request.params.temperature,
            'top_p': request.params.topP,
            if (request.params.maxTokens != null)
              'num_predict': request.params.maxTokens,
          },
        });
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw LlmProviderException('Ollama HTTP ${resp.statusCode}');
      }
      final lines = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final obj = jsonDecode(line) as Map<String, dynamic>;
        final delta = (obj['message']?['content'] as String?) ?? '';
        final done = obj['done'] == true;
        if (delta.isNotEmpty || done) {
          yield LlmChunk(delta, tokens: delta.isEmpty ? 0 : 1, done: done);
        }
        if (done) break;
      }
    } finally {
      client.close(); // aborts the response on cancellation or completion
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    if (!capabilities.contains(LlmCapability.embeddings)) {
      throw UnsupportedError('embeddings disabled for this provider');
    }
    final resp = await http.post(
      baseUrl.resolve('/api/embeddings'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'model': model, 'prompt': text}),
    );
    if (resp.statusCode != 200) {
      throw LlmProviderException('Ollama embeddings HTTP ${resp.statusCode}');
    }
    final obj = jsonDecode(resp.body) as Map<String, dynamic>;
    return (obj['embedding'] as List).cast<num>().map((n) => n.toDouble()).toList();
  }

  @override
  Future<void> dispose() async {}
}
