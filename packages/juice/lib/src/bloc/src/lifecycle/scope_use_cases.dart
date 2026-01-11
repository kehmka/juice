import 'package:flutter/foundation.dart';
import '../bloc_use_case.dart';
import '../bloc_scope.dart';
import 'lifecycle_bloc.dart';
import 'scope_state.dart';
import 'scope_events.dart';
import 'cleanup_barrier.dart';
import 'feature_scope.dart';

/// Use case to start tracking a scope.
class StartScopeUseCase extends BlocUseCase<LifecycleBloc, StartScopeEvent> {
  @override
  Future<void> execute(StartScopeEvent event) async {
    // Generate unique ID via monotonic counter
    final scopeId = bloc.generateScopeId();

    final info = ScopeInfo(
      id: scopeId,
      name: event.name,
      phase: ScopePhase.active,
      startedAt: DateTime.now(),
      scope: event.scope as FeatureScope,
    );

    emitUpdate(
      groupsToRebuild: {
        ScopeGroups.active,
        ScopeGroups.byName(event.name),
        ScopeGroups.byId(scopeId),
      },
      newState: bloc.state.copyWith(
        scopes: {...bloc.state.scopes, scopeId: info},
      ),
    );

    // Publish notification to subscribers
    bloc.publish(ScopeStartedNotification(
      scopeId: scopeId,
      scopeName: event.name,
      startedAt: info.startedAt,
    ));

    // Return the scope ID
    event.succeed(scopeId);
  }
}

/// Use case to end a scope (triggers cleanup sequence).
class EndScopeUseCase extends BlocUseCase<LifecycleBloc, EndScopeEvent> {
  @override
  Future<void> execute(EndScopeEvent event) async {
    // Resolve scope
    final info = _resolveScope(event);
    if (info == null) {
      event.succeed(EndScopeResult.notFound);
      return;
    }

    // Already ending? Await the in-flight operation instead of returning dummy.
    if (info.phase == ScopePhase.ending) {
      final inFlight = bloc.getEndingFuture(info.id);
      if (inFlight != null) {
        // Return the same result as the operation already in progress
        event.succeed(await inFlight);
        return;
      }
      // Invariant breach: phase is ending but no future tracked.
      // Log and proceed safely - treat as already ended.
      assert(() {
        debugPrint(
            'LifecycleBloc: phase==ending but no in-flight future for ${info.id}');
        return true;
      }());
      event.succeed(EndScopeResult.notFound);
      return;
    }

    // Idempotent: use getOrCreateEndingFuture to handle concurrent calls
    final result = await bloc.getOrCreateEndingFuture(
      info.id,
      () => _doEnd(info),
    );
    event.succeed(result);
  }

  ScopeInfo? _resolveScope(EndScopeEvent event) {
    if (event.scopeId != null) {
      return bloc.state.scopes[event.scopeId];
    }
    if (event.scopeName != null) {
      // AMBIGUOUS: When multiple scopes share the same name, returns the
      // first active one found. For correctness, prefer ending by scopeId.
      // This is provided as legacy convenience only.
      return bloc.state.scopes.values
          .where(
              (s) => s.name == event.scopeName && s.phase == ScopePhase.active)
          .firstOrNull;
    }
    return null;
  }

  Future<EndScopeResult> _doEnd(ScopeInfo info) async {
    // 1. Mark as ending
    emitUpdate(
      groupsToRebuild: {
        ScopeGroups.active,
        ScopeGroups.byName(info.name),
        ScopeGroups.byId(info.id),
      },
      newState: bloc.state.copyWith(
        scopes: {
          ...bloc.state.scopes,
          info.id: info.copyWith(phase: ScopePhase.ending)
        },
      ),
    );

    // 2. Create barrier and publish ENDING notification
    final barrier = CleanupBarrier();
    bloc.publish(ScopeEndingNotification(
      scopeId: info.id,
      scopeName: info.name,
      barrier: barrier,
    ));

    // 3. Await cleanup barrier (with configurable timeout)
    // Note: wait() catches individual task errors - never throws
    final barrierResult = await barrier.wait(
      timeout: bloc.config.cleanupTimeout,
    );

    // 4. Notify on timeout (for logging/metrics)
    if (barrierResult.timedOut) {
      bloc.config.onCleanupTimeout?.call(info.id, info.name);
    }

    // 5. ALWAYS dispose blocs - timeout only affects cleanupCompleted flag
    // This guarantees disposal proceeds; timeout is informational only.
    await BlocScope.endFeature(info.scope);

    // 6. Remove from state
    final duration = DateTime.now().difference(info.startedAt);
    final newScopes = {...bloc.state.scopes}..remove(info.id);
    emitUpdate(
      groupsToRebuild: {
        ScopeGroups.active,
        ScopeGroups.byName(info.name),
        ScopeGroups.byId(info.id),
      },
      newState: bloc.state.copyWith(scopes: newScopes),
    );

    // 7. Publish ENDED notification
    bloc.publish(ScopeEndedNotification(
      scopeId: info.id,
      scopeName: info.name,
      duration: duration,
      cleanupCompleted: barrierResult.completed,
    ));

    return EndScopeResult(
      found: true,
      cleanupCompleted: barrierResult.completed,
      cleanupFailedCount: barrierResult.failedCount,
      duration: duration,
      cleanupTaskCount: barrierResult.taskCount,
    );
  }
}
