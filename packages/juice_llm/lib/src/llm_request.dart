import 'dart:typed_data';

/// One message in a chat-style prompt.
class LlmMessage {
  final LlmRole role;
  final String content;

  /// Optional image bytes for a vision-capable model. Ignored by text models.
  final List<Uint8List> images;

  const LlmMessage(this.role, this.content, {this.images = const []});

  const LlmMessage.system(String content) : this(LlmRole.system, content);
  const LlmMessage.user(String content, {List<Uint8List> images = const []})
      : this(LlmRole.user, content, images: images);
  const LlmMessage.assistant(String content)
      : this(LlmRole.assistant, content);
}

enum LlmRole { system, user, assistant }

/// Knobs for a single generation. Defaults are conservative; a provider maps
/// these onto its runtime and ignores any it can't honor.
class LlmSamplingParams {
  final double temperature;
  final double topP;
  final int? maxTokens;

  /// Sequences that, once produced, end generation.
  final List<String> stop;

  const LlmSamplingParams({
    this.temperature = 0.7,
    this.topP = 0.95,
    this.maxTokens,
    this.stop = const [],
  });
}

/// A request to generate a completion. Carries its own [requestId] so a session
/// (and its `llm:gen:<requestId>` rebuild group) can be addressed before the
/// first token — UIs render the wait immediately.
class LlmRequest {
  final String requestId;
  final List<LlmMessage> messages;
  final LlmSamplingParams params;

  const LlmRequest({
    required this.requestId,
    required this.messages,
    this.params = const LlmSamplingParams(),
  });
}

/// One streamed step of a completion: a text delta, optionally terminal.
///
/// A provider's `generate` stream MUST react to listener cancellation by
/// stopping the runtime — cancellation is out-of-band, not a queued event.
class LlmChunk {
  /// The text produced since the previous chunk (may be empty on a terminal
  /// marker chunk).
  final String textDelta;

  /// Tokens produced this chunk (for accounting; 0 if the runtime doesn't
  /// report it).
  final int tokens;

  /// True on the final chunk of a completion.
  final bool done;

  const LlmChunk(this.textDelta, {this.tokens = 0, this.done = false});

  const LlmChunk.done() : this('', done: true);
}
