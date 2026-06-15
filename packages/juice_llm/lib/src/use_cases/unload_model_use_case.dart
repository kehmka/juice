import 'package:juice/juice.dart';

import '../llm_events.dart';
import '../llm_bloc.dart';
import '../llm_state.dart';

/// Handles [UnloadModelEvent] — free the runtime. Fail-loud if a generation is
/// active (cancel it first).
class UnloadModelUseCase extends BlocUseCase<LlmBloc, UnloadModelEvent> {
  @override
  Future<void> execute(UnloadModelEvent event) async {
    if (bloc.isGenerating) {
      emitUpdate(
        newState: bloc.state.copyWith(
          error: 'Cannot unload while a generation is active (cancel it first)',
        ),
        groupsToRebuild: {LlmGroups.model},
      );
      return;
    }

    try {
      await bloc.provider.unload();
      emitUpdate(
        newState: bloc.state.copyWith(
          modelStatus: LlmModelStatus.absent,
          activeModelId: null,
          error: null,
        ),
        groupsToRebuild: {LlmGroups.model},
      );
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(
          modelStatus: LlmModelStatus.error,
          error: e.toString(),
        ),
        groupsToRebuild: {LlmGroups.model},
        error: e,
      );
    }
  }
}
