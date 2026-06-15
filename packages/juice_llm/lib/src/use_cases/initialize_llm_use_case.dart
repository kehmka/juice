import 'package:juice/juice.dart';

import '../llm_events.dart';
import '../llm_bloc.dart';
import '../llm_state.dart';

/// Handles [InitializeLlmEvent] — apply config, probe whether the initial
/// model is already present, and auto-load it if so.
class InitializeLlmUseCase extends BlocUseCase<LlmBloc, InitializeLlmEvent> {
  @override
  Future<void> execute(InitializeLlmEvent event) async {
    bloc.configure(event.config);

    final model = event.config.initialModel;
    final source = event.config.modelSource;
    final resolve = event.config.resolvePath;

    // No model declared, or no way to locate it → stay absent (the Echo
    // default provider still loads on demand via LoadModelEvent).
    if (model == null || source == null || resolve == null) {
      emitUpdate(
        newState: bloc.state.copyWith(modelStatus: LlmModelStatus.absent),
        groupsToRebuild: {LlmGroups.model},
      );
      return;
    }

    final present = await source.isPresent(model, resolve(model));
    emitUpdate(
      newState: bloc.state.copyWith(
        modelStatus:
            present ? LlmModelStatus.fetched : LlmModelStatus.absent,
        activeModelId: present ? model.id : null,
      ),
      groupsToRebuild: {LlmGroups.model},
    );

    if (present) bloc.send(LoadModelEvent(model));
  }
}
