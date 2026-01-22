import 'package:juice/juice.dart';

import '../path_resolver.dart';
import '../route_context.dart';
import '../route_guard.dart';
import '../routing_bloc.dart';
import '../routing_errors.dart';
import '../routing_events.dart';
import '../routing_state.dart';
import '../routing_types.dart';

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
    );
  }

  Future<void> _executeNavigation({
    required String path,
    Object? extra,
    required bool replace,
    RouteTransition? transition,
    required int redirectCount,
  }) async {
    final config = bloc.config;
    final resolver = bloc.pathResolver;

    // Check redirect limit
    if (redirectCount >= config.maxRedirects) {
      emitFailure(
        newState: bloc.state.copyWith(
          error: RedirectLoopError(
            redirectChain: [], // Could track chain if needed
            maxRedirects: config.maxRedirects,
          ),
          clearPending: true,
        ),
        groupsToRebuild: {RoutingGroups.error, RoutingGroups.pending},
      );
      _processQueue();
      return;
    }

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

    // Collect guards (global + route), sort by priority
    final guards = <RouteGuard>[
      ...config.globalGuards,
      ...resolved.route.guards,
    ];
    guards.sort((a, b) => a.priority.compareTo(b.priority));

    // Set pending navigation state
    emitUpdate(
      newState: bloc.state.copyWith(
        pending: PendingNavigation(
          targetPath: path,
          guardsCompleted: 0,
          totalGuards: guards.length,
          redirectCount: redirectCount,
        ),
        clearError: true,
      ),
      groupsToRebuild: {RoutingGroups.pending},
    );

    // Run guards pipeline
    final context = RouteContext(
      targetPath: path,
      params: resolved.params,
      query: resolved.query,
      currentState: bloc.state,
      targetRoute: resolved.route,
    );

    for (var i = 0; i < guards.length; i++) {
      final guard = guards[i];

      // Update pending state with current guard
      emitUpdate(
        newState: bloc.state.copyWith(
          pending: bloc.state.pending?.copyWith(
            guardsCompleted: i,
            currentGuardName: guard.name,
          ),
        ),
        groupsToRebuild: {RoutingGroups.pending},
      );

      // Execute guard
      GuardResult result;
      try {
        result = await guard.check(context);
      } catch (e, stackTrace) {
        emitFailure(
          newState: bloc.state.copyWith(
            error: GuardExceptionError(
              path: path,
              guardName: guard.name,
              exception: e,
              stackTrace: stackTrace,
            ),
            clearPending: true,
          ),
          groupsToRebuild: {RoutingGroups.error, RoutingGroups.pending},
        );
        _processQueue();
        return;
      }

      // Handle result
      switch (result) {
        case AllowResult():
          // Continue to next guard
          continue;

        case RedirectResult():
          log('Guard ${guard.name} redirecting to ${result.path}');
          // Restart navigation with redirect path
          await _executeNavigation(
            path: result.path,
            extra: null,
            replace: replace,
            transition: transition,
            redirectCount: redirectCount + 1,
          );
          return;

        case BlockResult():
          emitFailure(
            newState: bloc.state.copyWith(
              error: GuardBlockedError(
                path: path,
                guardName: guard.name,
                reason: result.reason,
              ),
              clearPending: true,
            ),
            groupsToRebuild: {RoutingGroups.error, RoutingGroups.pending},
          );
          _processQueue();
          return;
      }
    }

    // All guards passed - commit navigation
    _commitNavigation(
      resolved: resolved,
      extra: extra,
      replace: replace,
      transition: transition,
    );
  }

  void _commitNavigation({
    required ResolvedRoute resolved,
    Object? extra,
    required bool replace,
    RouteTransition? transition,
  }) {
    final now = DateTime.now();

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

    emitUpdate(
      newState: bloc.state.copyWith(
        stack: newStack,
        history: [...bloc.state.history, historyEntry],
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
