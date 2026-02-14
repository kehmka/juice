import '../route_context.dart';
import '../route_guard.dart';
import '../routing_config.dart';
import '../routing_state.dart';
import '../routing_types.dart';

/// Result of running the guard pipeline.
sealed class GuardPipelineResult {
  const GuardPipelineResult();
}

/// All guards passed — navigation may proceed.
final class GuardPipelineAllowed extends GuardPipelineResult {
  const GuardPipelineAllowed();
}

/// A guard redirected to a different path.
final class GuardPipelineRedirected extends GuardPipelineResult {
  /// The path to redirect to.
  final String redirectPath;

  /// The accumulated redirect chain including this redirect.
  final List<String> redirectChain;

  const GuardPipelineRedirected({
    required this.redirectPath,
    required this.redirectChain,
  });
}

/// A guard blocked navigation.
final class GuardPipelineBlocked extends GuardPipelineResult {
  /// The path that was blocked.
  final String path;

  /// Name of the guard that blocked.
  final String guardName;

  /// Optional reason for blocking.
  final String? reason;

  const GuardPipelineBlocked({
    required this.path,
    required this.guardName,
    this.reason,
  });
}

/// A guard threw an exception.
final class GuardPipelineFailed extends GuardPipelineResult {
  /// The path being navigated to when the exception occurred.
  final String path;

  /// Name of the guard that threw.
  final String guardName;

  /// The exception thrown.
  final Object exception;

  /// Stack trace from the exception.
  final StackTrace? stackTrace;

  const GuardPipelineFailed({
    required this.path,
    required this.guardName,
    required this.exception,
    this.stackTrace,
  });
}

/// A redirect loop was detected.
final class GuardPipelineLoopDetected extends GuardPipelineResult {
  /// The full redirect chain that caused the loop.
  final List<String> redirectChain;

  /// Maximum redirects allowed.
  final int maxRedirects;

  const GuardPipelineLoopDetected({
    required this.redirectChain,
    required this.maxRedirects,
  });
}

/// Runs the guard pipeline for a navigation attempt.
///
/// Collects global + route guards, sorts by priority, and executes them
/// in order. Handles redirect chains with loop detection.
///
/// [emitUpdate] is called to update pending navigation state as guards run.
/// [log] is called for debug logging.
Future<GuardPipelineResult> runGuardPipeline({
  required String path,
  required RoutingConfig config,
  required RoutingState currentState,
  required RouteConfig targetRoute,
  required Map<String, String> params,
  required Map<String, String> query,
  required int redirectCount,
  required List<String> redirectChain,
  required void Function({
    required RoutingState newState,
    required Set<String> groupsToRebuild,
  }) emitUpdate,
  required void Function(String message) log,
}) async {
  // Check redirect limit
  if (redirectCount >= config.maxRedirects) {
    return GuardPipelineLoopDetected(
      redirectChain: redirectChain,
      maxRedirects: config.maxRedirects,
    );
  }

  // Collect guards (global + route), sort by priority
  final guards = <RouteGuard>[
    ...config.globalGuards,
    ...targetRoute.guards,
  ];
  guards.sort((a, b) => a.priority.compareTo(b.priority));

  // Set pending navigation state
  emitUpdate(
    newState: currentState.copyWith(
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
    params: params,
    query: query,
    currentState: currentState,
    targetRoute: targetRoute,
  );

  for (var i = 0; i < guards.length; i++) {
    final guard = guards[i];

    // Update pending state with current guard
    emitUpdate(
      newState: currentState.copyWith(
        pending: PendingNavigation(
          targetPath: path,
          guardsCompleted: i,
          totalGuards: guards.length,
          redirectCount: redirectCount,
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
      return GuardPipelineFailed(
        path: path,
        guardName: guard.name,
        exception: e,
        stackTrace: stackTrace,
      );
    }

    // Handle result
    switch (result) {
      case AllowResult():
        continue;

      case RedirectResult():
        log('Guard ${guard.name} redirecting to ${result.path}');
        return GuardPipelineRedirected(
          redirectPath: result.path,
          redirectChain: [...redirectChain, result.path],
        );

      case BlockResult():
        return GuardPipelineBlocked(
          path: path,
          guardName: guard.name,
          reason: result.reason,
        );
    }
  }

  return const GuardPipelineAllowed();
}
