import 'package:flutter/foundation.dart';
import '../bloc_use_case.dart';
import '../bloc_scope.dart';
import 'scope_lifecycle_bloc.dart';
import 'scope_state.dart';
import 'scope_events.dart';
import 'cleanup_barrier.dart';
import 'feature_scope.dart';

/// Use case to start tracking a scope.
class StartScopeUseCase
    extends BlocUseCase<ScopeLifecycleBloc, StartScopeEvent> {
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
class EndScopeUseCase extends BlocUseCase<ScopeLifecycleBloc, EndScopeEvent> {
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
        try {
          event.succeed(await inFlight);
        } catch (e, st) {
          event.fail(e, st);
        }
        return;
      }
      // Invariant breach: phase is ending but no future tracked.
      // Log and proceed safely - treat as already ended.
      assert(() {
        debugPrint(
            'ScopeLifecycleBloc: phase==ending but no in-flight future for ${info.id}');
        return true;
      }());
      event.succeed(EndScopeResult.notFound);
      return;
    }

    // Idempotent: use getOrCreateEndingFuture to handle concurrent calls
    // The event must ALWAYS complete: `FeatureScope.end()` awaits
    // `event.result`, and an exception that skipped `succeed` left it hanging
    // forever (a feature bloc whose close() threw did exactly that).
    try {
      final result = await bloc.getOrCreateEndingFuture(
        info.id,
        () => _doEnd(info),
      );
      event.succeed(result);
    } catch (e, st) {
      event.fail(e, st);
    }
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
    // A bloc whose close() throws must not strand the scope in `ending`:
    // every managed bloc is still closed and cleared (endFeature waits for
    // all of them), the scope is still removed and ENDED still published,
    // and only then is the error rethrown to the caller.
    Object? closeError;
    StackTrace? closeStack;
    try {
      await BlocScope.endFeature(info.scope);
    } catch (e, st) {
      closeError = e;
      closeStack = st;
    }

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

    if (closeError != null) {
      Error.throwWithStackTrace(closeError, closeStack!);
    }

    return EndScopeResult(
      found: true,
      cleanupCompleted: barrierResult.completed,
      cleanupFailedCount: barrierResult.failedCount,
      duration: duration,
      cleanupTaskCount: barrierResult.taskCount,
    );
  }
}
