import 'package:juice/juice.dart';

import '../llm_bloc.dart';
import '../llm_events.dart';
import '../llm_state.dart';

/// Handles [GenerateEvent] — stream a completion into a [GenerationSession].
///
/// `sequential`, so one generation runs at a time (a single runtime context);
/// queued events run in order. Each chunk accumulates text and emits on the
/// session's `llm:gen:<id>` group, **throttled** (the bloc coalesces to ≤ one
/// emission per `config.streamThrottle`). Whatever ends the stream — natural
/// completion, error, or a concurrent [CancelGenerationEvent] — funnels
/// through one terminal emission, so the session always reaches a terminal
/// status and the queue is never wedged.
///
/// Fail-loud: generating with no ready model produces an immediately-failed
/// session, never a silent wait for a model that was never requested.
class GenerateUseCase extends BlocUseCase<LlmBloc, GenerateEvent> {
  @override
  Future<void> execute(GenerateEvent event) async {
    final req = event.request;
    final groups = {
      LlmGroups.gen(req.requestId),
      LlmGroups.sessions,
      LlmGroups.any,
    };

    if (!bloc.state.isReady) {
      final failed = GenerationSession(
        requestId: req.requestId,
        status: SessionStatus.failed,
        error: 'No model loaded — load a model before generating',
      );
      emitUpdate(
        newState: bloc.state.copyWith(sessions: bloc.upsertSession(failed)),
        groupsToRebuild: groups,
      );
      return;
    }

    // Session appears as it starts streaming (UIs render the wait).
    var current = GenerationSession(
        requestId: req.requestId, status: SessionStatus.streaming);
    emitUpdate(
      newState: bloc.state.copyWith(sessions: bloc.upsertSession(current)),
      groupsToRebuild: groups,
    );

    final buffer = StringBuffer();
    var tokens = 0;

    final outcome = await bloc.beginGeneration(
      req,
      onChunk: (chunk) {
        buffer.write(chunk.textDelta);
        tokens += chunk.tokens;
        current = current.copyWith(
            text: buffer.toString(),
            tokens: tokens,
            status: SessionStatus.streaming);
        final snapshot = current; // capture this chunk's accumulated text
        bloc.scheduleStreamEmit(() {
          emitUpdate(
            newState:
                bloc.state.copyWith(sessions: bloc.upsertSession(snapshot)),
            groupsToRebuild: groups,
          );
        });
      },
    );

    // One terminal emission, unthrottled, based on how the stream ended.
    final SessionStatus terminal;
    String? error;
    switch (outcome.kind) {
      case GenOutcomeKind.done:
        terminal = SessionStatus.done;
      case GenOutcomeKind.cancelled:
        terminal = SessionStatus.cancelled;
      case GenOutcomeKind.error:
        terminal = SessionStatus.failed;
        error = outcome.error?.toString();
    }
    final finalSession =
        current.copyWith(status: terminal, error: error);
    bloc.flushStreamEmit(() {
      emitUpdate(
        newState:
            bloc.state.copyWith(sessions: bloc.upsertSession(finalSession)),
        groupsToRebuild: groups,
      );
    });
  }
}
