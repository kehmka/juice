import 'package:juice/juice.dart';

import '../llm_events.dart';
import '../llm_bloc.dart';
import '../llm_state.dart';

/// Handles [LoadModelEvent] — load weights into the runtime.
///
/// Fail-loud guards:
/// - refuses to load while a generation is active (no load-under-generate);
/// - a provider load failure surfaces in `state.error` and leaves status
///   `error` — no fallback model is ever silently substituted.
///
/// The Echo default provider ignores the path; a real provider loads the file
/// at `config.resolvePath(model)`.
class LoadModelUseCase extends BlocUseCase<LlmBloc, LoadModelEvent> {
  @override
  Future<void> execute(LoadModelEvent event) async {
    if (bloc.isGenerating) {
      emitUpdate(
        newState: bloc.state.copyWith(
          error: 'Cannot load a model while a generation is active '
              '(cancel it first)',
        ),
        groupsToRebuild: {LlmGroups.model},
      );
      return;
    }

    final path = bloc.config.resolvePath?.call(event.model) ?? event.model.id;

    emitUpdate(
      newState: bloc.state.copyWith(
        modelStatus: LlmModelStatus.loading,
        activeModelId: event.model.id,
        error: null,
      ),
      groupsToRebuild: {LlmGroups.model},
    );

    try {
      await bloc.provider.load(path, bloc.config.loadOptions);
      emitUpdate(
        newState: bloc.state.copyWith(modelStatus: LlmModelStatus.ready),
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
