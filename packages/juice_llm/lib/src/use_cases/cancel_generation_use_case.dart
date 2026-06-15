import 'package:juice/juice.dart';

import '../llm_bloc.dart';
import '../llm_events.dart';

/// Handles [CancelGenerationEvent] — stop the in-flight generation.
///
/// `concurrent` (not `sequential`), so it runs *during* the streaming
/// [GenerateUseCase]: it cancels the provider stream, which completes that
/// generation's outcome as `cancelled`. The generate use case then emits the
/// single terminal `cancelled` session — this use case deliberately does not
/// touch session state, keeping one finalize point.
///
/// Cancelling an unknown / already-finished id is a no-op (idempotent).
class CancelGenerationUseCase
    extends BlocUseCase<LlmBloc, CancelGenerationEvent> {
  @override
  Future<void> execute(CancelGenerationEvent event) async {
    if (bloc.activeRequestId != event.requestId) return; // not streaming
    await bloc.stopGeneration();
  }
}
