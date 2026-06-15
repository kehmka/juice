import 'package:juice/juice.dart';

import '../llm_bloc.dart';
import '../llm_events.dart';
import '../llm_model.dart';

/// Handles [EmbedEvent] — compute an embedding via the provider and complete
/// the event's result future.
///
/// Fail-loud: no ready model, or a model without the `embeddings` capability,
/// fails the result rather than returning a meaningless vector.
class EmbedUseCase extends BlocUseCase<LlmBloc, EmbedEvent> {
  @override
  Future<void> execute(EmbedEvent event) async {
    if (!bloc.state.isReady) {
      event.fail(StateError('No model loaded — cannot embed'));
      return;
    }
    if (!bloc.provider.capabilities.contains(LlmCapability.embeddings)) {
      event.fail(UnsupportedError(
          'Loaded model does not support embeddings'));
      return;
    }
    try {
      final vector = await bloc.provider.embed(event.text);
      event.succeed(vector);
    } catch (e, st) {
      event.fail(e, st);
    }
  }
}
