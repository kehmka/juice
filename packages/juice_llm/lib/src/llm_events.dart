import 'package:juice/juice.dart';

import 'llm_config.dart';
import 'llm_model.dart';
import 'llm_request.dart';

/// Base class for LLM events.
abstract class LlmEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Apply config; probe whether the model is already on disk; optionally
/// auto-load it.
class InitializeLlmEvent extends LlmEvent {
  final LlmConfig config;
  InitializeLlmEvent({required this.config});
}

/// Download [model]'s weights via the [ModelSource], streaming progress.
class FetchModelEvent extends LlmEvent {
  final LlmModel model;
  FetchModelEvent(this.model);
}

/// Load the (already-present) [model] into the runtime. Fails loud if any
/// generation session is active.
class LoadModelEvent extends LlmEvent {
  final LlmModel model;
  LoadModelEvent(this.model);
}

/// Unload the runtime (free weights). Fails loud if a session is active.
class UnloadModelEvent extends LlmEvent {}

/// Run a completion; its session streams under `llm:gen:<requestId>`.
class GenerateEvent extends LlmEvent {
  final LlmRequest request;
  GenerateEvent(this.request);
}

/// Cancel an in-flight (or queued) generation by id — stops the runtime
/// out-of-band.
class CancelGenerationEvent extends LlmEvent {
  final String requestId;
  CancelGenerationEvent(this.requestId);
}

/// Compute an embedding for [text]. The vector rides this event's own
/// completer (the family's result-event shape) rather than state — an
/// embedding is a one-shot value, not UI a widget watches. Await [result];
/// the use case calls [succeed] / [fail].
class EmbedEvent extends LlmEvent {
  final String text;
  EmbedEvent(this.text);

  final Completer<List<double>> _completer = Completer<List<double>>();

  /// Completes when the embedding use case finishes.
  Future<List<double>> get result => _completer.future;

  void succeed(List<double> value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }

  void fail(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
      _completer.future.ignore();
    }
  }
}

/// Drop a retained terminal session from state (consumers read, then evict).
class EvictSessionEvent extends LlmEvent {
  final String requestId;
  EvictSessionEvent(this.requestId);
}
