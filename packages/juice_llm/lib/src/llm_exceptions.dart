/// Thrown by an [LlmProvider] for a loud, non-recoverable runtime failure
/// (load OOM, format mismatch, decode error). The bloc surfaces it in
/// `state.error` / a session's `error`; it is never swallowed and no fallback
/// model is ever silently substituted.
class LlmProviderException implements Exception {
  final String message;
  final Object? cause;
  const LlmProviderException(this.message, {this.cause});

  @override
  String toString() =>
      'LlmProviderException: $message${cause == null ? '' : ' ($cause)'}';
}

/// Thrown by a [ModelSource] when fetched bytes fail their SHA-256 check. The
/// partial/corrupt file is deleted before this throws — unverified weights are
/// never left on disk to be loaded later.
class ModelChecksumException implements Exception {
  final String modelId;
  final String expected;
  final String actual;
  const ModelChecksumException(this.modelId, this.expected, this.actual);

  @override
  String toString() =>
      'ModelChecksumException($modelId): expected $expected, got $actual';
}
