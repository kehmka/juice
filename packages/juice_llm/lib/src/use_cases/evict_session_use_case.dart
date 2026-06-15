import 'package:juice/juice.dart';

import '../llm_bloc.dart';
import '../llm_events.dart';
import '../llm_state.dart';

/// Handles [EvictSessionEvent] — drop a retained terminal session from state.
/// A still-active (non-terminal) session is left alone — never evict a
/// generation that's in flight.
class EvictSessionUseCase extends BlocUseCase<LlmBloc, EvictSessionEvent> {
  @override
  Future<void> execute(EvictSessionEvent event) async {
    final s = bloc.session(event.requestId);
    if (s == null || !s.isTerminal) return;
    emitUpdate(
      newState:
          bloc.state.copyWith(sessions: bloc.removeSession(event.requestId)),
      groupsToRebuild: {
        LlmGroups.gen(event.requestId),
        LlmGroups.sessions,
        LlmGroups.any,
      },
    );
  }
}
