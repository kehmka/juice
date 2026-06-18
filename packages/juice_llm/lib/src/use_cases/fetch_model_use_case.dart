import 'package:juice/juice.dart';

import '../llm_events.dart';
import '../llm_bloc.dart';
import '../llm_state.dart';

/// Handles [FetchModelEvent] — download the weights through the [ModelSource],
/// streaming progress, then mark the model `fetched`.
///
/// Fail-loud: no source configured, or a fetch/checksum failure, sets
/// `modelStatus: error` with the reason. A checksum mismatch deletes the
/// corrupt file inside the source — unverified weights are never left behind.
class FetchModelUseCase extends BlocUseCase<LlmBloc, FetchModelEvent> {
  @override
  Future<void> execute(FetchModelEvent event) async {
    final source = bloc.modelSource;
    final resolve = bloc.config.resolvePath;
    if (source == null || resolve == null) {
      emitUpdate(
        newState: bloc.state.copyWith(
          modelStatus: LlmModelStatus.error,
          error: 'fetchModel called with no ModelSource/resolvePath configured',
        ),
        groupsToRebuild: {LlmGroups.model},
      );
      return;
    }

    final path = resolve(event.model);
    emitUpdate(
      newState: bloc.state.copyWith(
        modelStatus: LlmModelStatus.fetching,
        activeModelId: event.model.id,
        fetchProgress: 0.0,
        error: null,
      ),
      groupsToRebuild: {LlmGroups.model, LlmGroups.fetch},
    );

    try {
      await for (final p in source.fetch(event.model, path)) {
        emitUpdate(
          newState: bloc.state.copyWith(fetchProgress: p.fraction),
          groupsToRebuild: {LlmGroups.fetch},
        );
        if (p.done) break;
      }
      emitUpdate(
        newState: bloc.state.copyWith(
          modelStatus: LlmModelStatus.fetched,
          fetchProgress: null,
        ),
        groupsToRebuild: {LlmGroups.model, LlmGroups.fetch},
      );
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(
          modelStatus: LlmModelStatus.error,
          fetchProgress: null,
          error: e.toString(),
        ),
        groupsToRebuild: {LlmGroups.model, LlmGroups.fetch},
        error: e,
      );
    }
  }
}
