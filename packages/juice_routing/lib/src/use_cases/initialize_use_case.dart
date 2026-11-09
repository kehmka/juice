import 'package:juice/juice.dart';

import '../path_resolver.dart';
import '../routing_bloc.dart';
import '../routing_errors.dart';
import '../routing_events.dart';
import '../routing_state.dart';
import '../routing_types.dart';
import 'guard_pipeline.dart';

/// Use case for initializing the routing system.
///
/// Creates the path resolver, then enters the initial path the way every
/// other navigation enters a path: through the guard pipeline. A guard may
/// allow it, redirect it (the redirect target is guarded in turn), or block
/// it. Only an allowed path is seeded onto the stack.
///
/// A blocked initial path, a guard that throws, or a redirect loop leaves the
/// stack EMPTY with the error in state — the same shape an unknown initial
/// path produces. Nothing is shown in place of a route a guard refused.
class InitializeUseCase
    extends BlocUseCase<RoutingBloc, InitializeRoutingEvent> {
  @override
  Future<void> execute(InitializeRoutingEvent event) async {
    final config = event.config;
    final initialPath = event.initialPath ?? config.initialPath;

    // Create and store path resolver in bloc
    final resolver = PathResolver(config);
    bloc.setConfig(config, resolver);

    await _enter(
      path: initialPath,
      redirectCount: 0,
      redirectChain: [initialPath],
    );

    // A navigation that arrived while the guards ran was queued behind the
    // pending initial entry (the platform's cold-start report, typically).
    final queued = bloc.dequeueNavigation();
    if (queued != null) {
      log('Processing queued navigation: ${queued.path}');
      bloc.send(queued);
    }
  }

  Future<void> _enter({
    required String path,
    required int redirectCount,
    required List<String> redirectChain,
  }) async {
    final resolved = bloc.pathResolver.resolve(path);
    if (resolved == null) {
      _fail(RouteNotFoundError(path));
      return;
    }

    final result = await runGuardPipeline(
      path: path,
      config: bloc.config,
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
        _commit(resolved);

      case GuardPipelineRedirected():
        await _enter(
          path: result.redirectPath,
          redirectCount: redirectCount + 1,
          redirectChain: result.redirectChain,
        );

      case GuardPipelineBlocked():
        _fail(GuardBlockedError(
          path: result.path,
          guardName: result.guardName,
          reason: result.reason,
        ));

      case GuardPipelineFailed():
        _fail(GuardExceptionError(
          path: result.path,
          guardName: result.guardName,
          exception: result.exception,
          stackTrace: result.stackTrace,
        ));

      case GuardPipelineLoopDetected():
        _fail(RedirectLoopError(
          redirectChain: result.redirectChain,
          maxRedirects: result.maxRedirects,
        ));
    }
  }

  void _commit(ResolvedRoute resolved) {
    final now = DateTime.now();

    final entry = StackEntry(
      route: resolved.route,
      path: resolved.matchedPath,
      params: resolved.params,
      query: resolved.query,
      key: generateEntryKey(),
      pushedAt: now,
      scopeId: resolved.route.scopeName != null
          ? '${resolved.route.scopeName}_${generateEntryKey()}'
          : null,
    );

    final historyEntry = HistoryEntry(
      path: resolved.matchedPath,
      timestamp: now,
      type: NavigationType.push,
    );

    emitUpdate(
      newState: RoutingState(
        stack: [entry],
        history: [historyEntry],
        isInitialized: true,
      ),
      groupsToRebuild: RoutingGroups.all,
    );

    log('Initialized with path: ${resolved.matchedPath}');
  }

  /// The initial path could not be entered: no stack, the error in state.
  void _fail(RoutingError error) {
    log('Initialization failed: $error');
    emitFailure(
      newState: bloc.state.copyWith(
        error: error,
        isInitialized: true,
        clearPending: true,
      ),
      groupsToRebuild: {RoutingGroups.error, RoutingGroups.pending},
    );
  }
}
