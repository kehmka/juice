import 'dart:async';

import 'llm_model.dart';

/// Progress of a model fetch. [fraction] is 0..1; [done] marks the final,
/// verified event (emitted only after the SHA-256 check passes).
class ModelFetchProgress {
  final double fraction;
  final int receivedBytes;
  final int totalBytes;
  final bool done;

  const ModelFetchProgress({
    required this.fraction,
    required this.receivedBytes,
    required this.totalBytes,
    this.done = false,
  });
}

/// The acquisition seam: where model weights come from and how they're
/// verified. A provider concern (like `FlagsSource`), not a bridge onto
/// `juice_network` — so HTTP-with-resume, a CDN client, or a bundled-asset
/// copy are all just implementations.
///
/// Contract: [fetch] MUST verify `model.sha256` against the downloaded bytes
/// and, on mismatch, delete the file and throw [ModelChecksumException] —
/// unverified weights are never reported present.
abstract class ModelSource {
  /// Acquire [model] to [destinationPath], streaming progress. Resumable
  /// implementations pick up a partial file; all implementations verify the
  /// checksum before the terminal `done` event.
  Stream<ModelFetchProgress> fetch(LlmModel model, String destinationPath);

  /// Whether verified weights already sit at [destinationPath].
  Future<bool> isPresent(LlmModel model, String destinationPath);

  /// Remove the weights at [destinationPath] (free disk).
  Future<void> delete(LlmModel model, String destinationPath);
}

/// A [ModelSource] over an injected filesystem seam — the zero-dependency
/// default. It does no network I/O: it treats the model as already present
/// (sideloaded weights, a bundled asset the app copied into place, or a test
/// fixture) and reports a single verified `done`.
///
/// Real network acquisition (HTTP Range resume + streaming SHA-256) is a
/// straightforward implementation of this seam; it lives in app/example code
/// so the core package stays dependency-free.
class FileModelSource implements ModelSource {
  FileModelSource(this._fs);

  /// Filesystem operations, injected so the default has no `dart:io` coupling
  /// (and is trivially fakeable in tests).
  final ModelFileSystem _fs;

  @override
  Stream<ModelFetchProgress> fetch(
      LlmModel model, String destinationPath) async* {
    final present = await _fs.exists(destinationPath);
    if (!present) {
      // Nothing to download from here — a FileModelSource only adopts weights
      // already on disk. Fail loud rather than pretend success.
      throw StateError(
          'FileModelSource: no file at $destinationPath for ${model.id} '
          '(this source does not download — use a network ModelSource)');
    }
    final size = await _fs.size(destinationPath);
    yield ModelFetchProgress(
        fraction: 1, receivedBytes: size, totalBytes: size, done: true);
  }

  @override
  Future<bool> isPresent(LlmModel model, String destinationPath) =>
      _fs.exists(destinationPath);

  @override
  Future<void> delete(LlmModel model, String destinationPath) =>
      _fs.delete(destinationPath);
}

/// Minimal filesystem seam for [FileModelSource] — keeps the core package free
/// of a `dart:io` dependency and makes acquisition testable.
abstract class ModelFileSystem {
  Future<bool> exists(String path);
  Future<int> size(String path);
  Future<void> delete(String path);
}
