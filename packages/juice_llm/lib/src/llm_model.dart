/// What a model can do. A provider advertises its capabilities; the bloc
/// refuses operations a loaded model doesn't support (fail-loud, never a
/// silent no-op).
enum LlmCapability {
  /// Text completion / chat (the baseline).
  text,

  /// Embedding vectors via `embed()`.
  embeddings,

  /// Image input alongside text (multimodal).
  vision,
}

/// An immutable descriptor of a model the app may acquire and load.
///
/// The descriptor is data, not behavior: it tells [ModelSource] where to fetch
/// the weights and how to verify them, and tells the app what the model can do
/// and what its license obliges. The bytes themselves live on the filesystem
/// at a path the consumer chooses — never bundled into the app binary.
class LlmModel {
  /// Stable identifier, also the active-model key in state
  /// (e.g. `gemma-4-e2b-it-qat-q4`).
  final String id;

  /// Human-facing name for UI (e.g. "Gemma 4 E2B").
  final String displayName;

  /// Where to fetch the weights. May be a remote URL or a `file:` URI for a
  /// sideloaded model.
  final Uri source;

  /// Lowercase hex SHA-256 of the weights. [ModelSource] MUST verify this
  /// before reporting the model present — unverified weights never load.
  final String sha256;

  /// Total download size, for a disk preflight and download UX.
  final int sizeBytes;

  /// What the model supports once loaded.
  final Set<LlmCapability> capabilities;

  /// Maximum context window, in tokens.
  final int contextTokens;

  /// SPDX-ish license id (e.g. `Apache-2.0`). The app surfaces an acceptance
  /// flow before first fetch only when the license demands one — Gemma 4 is
  /// Apache-2.0 and does not; older generations / other families may.
  final String license;

  const LlmModel({
    required this.id,
    required this.displayName,
    required this.source,
    required this.sha256,
    required this.sizeBytes,
    this.capabilities = const {LlmCapability.text},
    this.contextTokens = 8192,
    this.license = 'unknown',
  });

  bool supports(LlmCapability c) => capabilities.contains(c);

  @override
  bool operator ==(Object other) => other is LlmModel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'LlmModel($id, ${(sizeBytes / 1e6).toStringAsFixed(0)}MB, '
      '${capabilities.map((c) => c.name).join("+")})';
}
