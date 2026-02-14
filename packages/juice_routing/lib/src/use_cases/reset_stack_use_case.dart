import 'package:juice/juice.dart';

import '../path_resolver.dart';
import '../routing_bloc.dart';
import '../routing_errors.dart';
import '../routing_events.dart';
import '../routing_state.dart';
import '../routing_types.dart';
import 'guard_pipeline.dart';

/// Use case for resetting the entire stack to a single new route.
///
/// Guards are run on the new path. If guards pass, the entire
/// stack is replaced with a single entry for the new path.
class ResetStackUseCase extends BlocUseCase<RoutingBloc, ResetStackEvent> {
  @override
  Future<void> execute(ResetStackEvent event) async {
    await _executeReset(
      path: event.path,
      extra: event.extra,
      redirectCount: 0,
      redirectChain: [event.path],
    );
  }

  Future<void> _executeReset({
    required String path,
    Object? extra,
    required int redirectCount,
    required List<String> redirectChain,
  }) async {
    final config = bloc.config;
    final resolver = bloc.pathResolver;

    // Resolve path
    final resolved = resolver.resolve(path);
    if (resolved == null) {
      emitFailure(
        newState: bloc.state.copyWith(
          error: RouteNotFoundError(path),
        ),
        groupsToRebuild: {RoutingGroups.error},
      );
      return;
    }

    // Run guard pipeline
    final result = await runGuardPipeline(
      path: path,
      config: config,
      currentState: bloc.state,
      targetRoute: resolved.route,
      params: resolved.params,
      query: resolved.query,
      redirectCount: redirectCount,
      redirectChain: redirectChain,
      emitUpdate: ({required newState, required groupsToRebuild}) {
        emitUpdate(newState: newState, groupsToRebuild: groupsToRebuild);
      },
      log: log,
    );

    switch (result) {
      case GuardPipelineAllowed():
        _commitReset(resolved: resolved, extra: extra);

      case GuardPipelineRedirected():
        await _executeReset(
          path: result.redirectPath,
          extra: null,
          redirectCount: redirectCount + 1,
          redirectChain: result.redirectChain,
        );

      case GuardPipelineBlocked():
        emitFailure(
          newState: bloc.state.copyWith(
            error: GuardBlockedError(
              path: result.path,
              guardName: result.guardName,
              reason: result.reason,
            ),
            clearPending: true,
          ),
          groupsToRebuild: {RoutingGroups.error, RoutingGroups.pending},
        );

      case GuardPipelineFailed():
        emitFailure(
          newState: bloc.state.copyWith(
            error: GuardExceptionError(
              path: result.path,
              guardName: result.guardName,
              exception: result.exception,
              stackTrace: result.stackTrace,
            ),
            clearPending: true,
          ),
          groupsToRebuild: {RoutingGroups.error, RoutingGroups.pending},
        );

      case GuardPipelineLoopDetected():
        emitFailure(
          newState: bloc.state.copyWith(
            error: RedirectLoopError(
              redirectChain: result.redirectChain,
              maxRedirects: result.maxRedirects,
            ),
            clearPending: true,
          ),
          groupsToRebuild: {RoutingGroups.error, RoutingGroups.pending},
        );
    }
  }

  void _commitReset({
    required ResolvedRoute resolved,
    Object? extra,
  }) {
    final now = DateTime.now();
    final config = bloc.config;

    // Create new stack entry
    final entry = StackEntry(
      route: resolved.route,
      path: resolved.matchedPath,
      params: resolved.params,
      query: resolved.query,
      extra: extra,
      key: generateEntryKey(),
      pushedAt: now,
      scopeId: resolved.route.scopeName != null
          ? '${resolved.route.scopeName}_${generateEntryKey()}'
          : null,
    );

    // Create history entry
    final historyEntry = HistoryEntry(
      path: resolved.matchedPath,
      timestamp: now,
      type: NavigationType.reset,
    );

    // Trim history if needed
    var newHistory = [...bloc.state.history, historyEntry];
    if (newHistory.length > config.maxHistorySize) {
      newHistory = newHistory.sublist(newHistory.length - config.maxHistorySize);
    }

    emitUpdate(
      newState: bloc.state.copyWith(
        stack: [entry],
        history: newHistory,
        clearPending: true,
        clearError: true,
      ),
      groupsToRebuild: {
        RoutingGroups.stack,
        RoutingGroups.current,
        RoutingGroups.pending,
        RoutingGroups.history,
      },
    );

    log('Reset stack to ${resolved.matchedPath}');
  }
}
