import 'package:juice/juice.dart';

import '../path_resolver.dart';
import '../route_context.dart';
import '../route_guard.dart';
import '../routing_bloc.dart';
import '../routing_errors.dart';
import '../routing_events.dart';
import '../routing_state.dart';
import '../routing_types.dart';

/// Use case for resetting the entire stack to a single new route.
///
/// Guards are run on the new path. If guards pass, the entire
/// stack is replaced with a single entry for the new path.
class ResetStackUseCase extends BlocUseCase<RoutingBloc, ResetStackEvent> {
  @override
  Future<void> execute(ResetStackEvent event) async {
    final config = bloc.config;
    final resolver = bloc.pathResolver;
    final path = event.path;

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

    var redirectCount = 0;

    for (var i = 0; i < guards.length; i++) {
      final guard = guards[i];

      // Update pending state
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
        return;
      }

      // Handle result
      switch (result) {
        case AllowResult():
          continue;

        case RedirectResult():
          // Check redirect limit
          redirectCount++;
          if (redirectCount >= config.maxRedirects) {
            emitFailure(
              newState: bloc.state.copyWith(
                error: RedirectLoopError(
                  redirectChain: [],
                  maxRedirects: config.maxRedirects,
                ),
                clearPending: true,
              ),
              groupsToRebuild: {RoutingGroups.error, RoutingGroups.pending},
            );
            return;
          }
          // Send new reset event with redirect path
          log('Guard ${guard.name} redirecting reset to ${result.path}');
          bloc.send(ResetStackEvent(path: result.path));
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
          return;
      }
    }

    // All guards passed - commit reset
    _commitReset(resolved: resolved, extra: event.extra);
  }

  void _commitReset({
    required ResolvedRoute resolved,
    Object? extra,
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

    // Create history entry
    final historyEntry = HistoryEntry(
      path: resolved.matchedPath,
      timestamp: now,
      type: NavigationType.reset,
    );

    emitUpdate(
      newState: bloc.state.copyWith(
        stack: [entry],
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

    log('Reset stack to ${resolved.matchedPath}');
  }
}
