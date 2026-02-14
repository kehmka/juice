import 'package:juice/juice.dart';

import '../path_resolver.dart';
import '../routing_bloc.dart';
import '../routing_errors.dart';
import '../routing_events.dart';
import '../routing_state.dart';
import '../routing_types.dart';
import 'guard_pipeline.dart';

/// Use case for navigating to a new path.
///
/// Handles:
/// - Path resolution
/// - Guard execution with redirect loop detection
/// - Stack management (push vs replace)
/// - History tracking
/// - Navigation queuing (depth 1, latest wins)
class NavigateUseCase extends BlocUseCase<RoutingBloc, NavigateEvent> {
  @override
  Future<void> execute(NavigateEvent event) async {
    // If already navigating, queue this navigation (latest wins)
    if (bloc.state.isNavigating) {
      bloc.queueNavigation(event);
      log('Navigation queued: ${event.path}');
      return;
    }

    await _executeNavigation(
      path: event.path,
      extra: event.extra,
      replace: event.replace,
      transition: event.transition,
      redirectCount: 0,
      redirectChain: [event.path],
    );
  }

  Future<void> _executeNavigation({
    required String path,
    Object? extra,
    required bool replace,
    RouteTransition? transition,
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
          clearPending: true,
        ),
        groupsToRebuild: {RoutingGroups.error, RoutingGroups.pending},
      );
      _processQueue();
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
        _commitNavigation(
          resolved: resolved,
          extra: extra,
          replace: replace,
          transition: transition,
        );

      case GuardPipelineRedirected():
        await _executeNavigation(
          path: result.redirectPath,
          extra: null,
          replace: replace,
          transition: transition,
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
        _processQueue();

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
        _processQueue();

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
        _processQueue();
    }
  }

  void _commitNavigation({
    required ResolvedRoute resolved,
    Object? extra,
    required bool replace,
    RouteTransition? transition,
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

    // Update stack
    final List<StackEntry> newStack;
    final NavigationType navType;

    if (replace && bloc.state.stack.isNotEmpty) {
      // Replace top entry
      newStack = [
        ...bloc.state.stack.sublist(0, bloc.state.stack.length - 1),
        entry,
      ];
      navType = NavigationType.replace;
    } else {
      // Push new entry
      newStack = [...bloc.state.stack, entry];
      navType = NavigationType.push;
    }

    // Create history entry
    final historyEntry = HistoryEntry(
      path: resolved.matchedPath,
      timestamp: now,
      type: navType,
    );

    // Trim history if needed
    var newHistory = [...bloc.state.history, historyEntry];
    if (newHistory.length > config.maxHistorySize) {
      newHistory = newHistory.sublist(newHistory.length - config.maxHistorySize);
    }

    emitUpdate(
      newState: bloc.state.copyWith(
        stack: newStack,
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

    log('Navigated to ${resolved.matchedPath} (${navType.name})');

    // Process any queued navigation
    _processQueue();
  }

  void _processQueue() {
    final queued = bloc.dequeueNavigation();
    if (queued != null) {
      log('Processing queued navigation: ${queued.path}');
      bloc.send(queued);
    }
  }
}
