# ScopeBloc Specification

> **Status:** Draft v1.2 (freeze candidate)
> **Package:** `juice` (core)
> **Purpose:** Reactive lifecycle events for FeatureScope

---

## Overview

ScopeBloc completes the FeatureScope story by providing reactive events that other blocs can subscribe to. FeatureScope remains a simple ID/key for registration; ScopeBloc adds the event layer with a **deterministic cleanup contract**.

**Before:** FeatureScope.end() → blocs disposed (no warning, no cleanup opportunity)

**After:** FeatureScope.end() → ScopeBloc publishes ScopeEndingEvent → subscribers register cleanup → barrier awaited → blocs disposed

---

## The Problem

Currently, when `FeatureScope.end()` is called:
1. All blocs in that scope are immediately closed
2. No opportunity for blocs to cleanup (cancel requests, save state, etc.)
3. Other blocs can't react to scope lifecycle
4. Race condition: bloc closed before it can process cleanup

```dart
// Current behavior - no cleanup opportunity
await checkoutScope.end();
// FetchBloc still has inflight requests for 'checkout' scope
// They complete after bloc is gone → orphaned callbacks
```

---

## The Solution

ScopeBloc is a permanent bloc that:
1. Tracks active scopes by unique ID (not just name)
2. Publishes lifecycle notifications (separate from command events)
3. Provides a **CleanupBarrier** so subscribers can register async cleanup
4. Guarantees: "broadcast ending → await cleanup → then dispose"

```dart
// New behavior - deterministic cleanup
await checkoutScope.end();
// 1. ScopeBloc publishes ScopeEndingEvent with CleanupBarrier
// 2. FetchBloc registers cleanup future on barrier
// 3. ScopeBloc awaits barrier (with timeout)
// 4. Blocs disposed cleanly
```

---

## Core Types

### CleanupBarrier

The contract that makes cleanup deterministic:

```dart
/// Result of waiting on cleanup barrier.
@immutable
class CleanupBarrierResult {
  /// All tasks completed before timeout
  final bool completed;

  /// Timeout was reached
  final bool timedOut;

  /// Number of tasks that threw exceptions
  final int failedCount;

  /// Total number of registered tasks
  final int taskCount;

  const CleanupBarrierResult({
    required this.completed,
    required this.timedOut,
    required this.failedCount,
    required this.taskCount,
  });

  /// True if all tasks finished successfully without timeout
  bool get allSucceeded => completed && failedCount == 0;
}

/// Collects cleanup futures from subscribers and awaits them.
class CleanupBarrier {
  final List<Future<void>> _futures = [];
  bool _closed = false;
  int _failedCount = 0;

  /// Subscribers call this to register cleanup work.
  /// Must be called synchronously when receiving ScopeEndingNotification.
  ///
  /// Returns true if added, false if barrier already closed.
  /// Does NOT throw - late registration is logged but doesn't crash.
  bool add(Future<void> cleanup) {
    if (_closed) {
      // Log via Juice logger if available, but don't crash
      assert(() {
        debugPrint('CleanupBarrier: add() called after close - '
            'cleanup task will not be awaited');
        return true;
      }());
      return false;
    }
    _futures.add(cleanup);
    return true;
  }

  /// Awaits all registered cleanup with timeout.
  ///
  /// Individual task failures are caught and counted, NOT propagated.
  /// This ensures scope disposal always completes deterministically.
  Future<CleanupBarrierResult> wait({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    _closed = true;

    if (_futures.isEmpty) {
      return const CleanupBarrierResult(
        completed: true,
        timedOut: false,
        failedCount: 0,
        taskCount: 0,
      );
    }

    final taskCount = _futures.length;

    // Wrap each future to catch individual failures
    final wrappedFutures = _futures.map((f) async {
      try {
        await f;
      } catch (e, stack) {
        _failedCount++;
        // Log but don't propagate
        assert(() {
          debugPrint('CleanupBarrier: cleanup task failed: $e\n$stack');
          return true;
        }());
      }
    }).toList();

    bool timedOut = false;
    try {
      await Future.wait(wrappedFutures).timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      assert(() {
        debugPrint('CleanupBarrier: timeout after $timeout - '
            '$taskCount tasks may still be running');
        return true;
      }());
    }

    return CleanupBarrierResult(
      completed: !timedOut,
      timedOut: timedOut,
      failedCount: _failedCount,
      taskCount: taskCount,
    );
  }

  int get pendingCount => _futures.length;
}
```

### ScopePhase

```dart
enum ScopePhase {
  active,   // Scope is running
  ending,   // Cleanup in progress
}
```

---

## State

```dart
@immutable
class ScopeState extends BlocState {
  /// Active scopes keyed by unique ID
  final Map<String, ScopeInfo> scopes;

  const ScopeState({
    this.scopes = const {},
  });

  /// Lookup by name (may return multiple if names collide)
  List<ScopeInfo> byName(String name) =>
      scopes.values.where((s) => s.name == name).toList();

  /// Check if any scope with this name is active
  bool isActive(String name) =>
      scopes.values.any((s) => s.name == name && s.phase == ScopePhase.active);

  @override
  ScopeState copyWith({
    Map<String, ScopeInfo>? scopes,
  }) {
    return ScopeState(
      scopes: scopes ?? this.scopes,
    );
  }
}

@immutable
class ScopeInfo {
  /// Unique identifier - primary key
  /// Generated via monotonic counter on ScopeBloc (deterministic, collision-free)
  final String id;

  /// Human-readable name (can collide across instances)
  final String name;

  /// Current phase
  final ScopePhase phase;

  /// When scope started
  final DateTime startedAt;

  /// Reference to FeatureScope for disposal
  final FeatureScope scope;

  const ScopeInfo({
    required this.id,
    required this.name,
    required this.phase,
    required this.startedAt,
    required this.scope,
  });

  ScopeInfo copyWith({ScopePhase? phase}) {
    return ScopeInfo(
      id: id,
      name: name,
      phase: phase ?? this.phase,
      startedAt: startedAt,
      scope: scope,
    );
  }
}
```

---

## Events

### Command Events (sent via `send()`)

```dart
/// Start tracking a scope
class StartScopeEvent extends EventBase with ResultEvent<String> {
  final String name;
  final FeatureScope scope;

  StartScopeEvent({
    required this.name,
    required this.scope,
  });
}
// Returns: scopeId (String)

/// End a scope (triggers cleanup sequence)
class EndScopeEvent extends EventBase with ResultEvent<EndScopeResult> {
  /// Scope ID (preferred) - unambiguous, always correct.
  final String? scopeId;

  /// Scope name (legacy convenience) - AMBIGUOUS when multiple scopes
  /// share the same name. When used, returns the first active scope found.
  /// For correctness, always prefer ending by scopeId.
  final String? scopeName;

  EndScopeEvent({this.scopeId, this.scopeName})
      : assert(scopeId != null || scopeName != null);
}

@immutable
class EndScopeResult {
  final bool found;
  final bool cleanupCompleted;  // false if timed out
  final int cleanupFailedCount; // tasks that threw exceptions
  final Duration duration;
  final int cleanupTaskCount;

  const EndScopeResult({
    required this.found,
    required this.cleanupCompleted,
    required this.cleanupFailedCount,
    required this.duration,
    required this.cleanupTaskCount,
  });

  /// Scope ended cleanly with all cleanup succeeded
  bool get success => found && cleanupCompleted && cleanupFailedCount == 0;

  /// Sentinel for "scope not found" / already ended
  static const notFound = EndScopeResult(
    found: false,
    cleanupCompleted: true,
    cleanupFailedCount: 0,
    duration: Duration.zero,
    cleanupTaskCount: 0,
  );
}
```

### Notification Events (published via `publish()`)

These go to subscribers, NOT through the command bus:

```dart
/// Base class for all scope notifications.
/// Enables type-safe filtering via stream.whereType<T>().
abstract class ScopeNotification {
  String get scopeId;
  String get scopeName;
}

/// Scope has started
class ScopeStartedNotification implements ScopeNotification {
  @override
  final String scopeId;
  @override
  final String scopeName;
  final DateTime startedAt;

  const ScopeStartedNotification({
    required this.scopeId,
    required this.scopeName,
    required this.startedAt,
  });
}

/// Scope is ending - register cleanup NOW
class ScopeEndingNotification implements ScopeNotification {
  @override
  final String scopeId;
  @override
  final String scopeName;
  final CleanupBarrier barrier;

  const ScopeEndingNotification({
    required this.scopeId,
    required this.scopeName,
    required this.barrier,
  });
}

/// Scope has ended - disposal complete
class ScopeEndedNotification implements ScopeNotification {
  @override
  final String scopeId;
  @override
  final String scopeName;
  final Duration duration;
  final bool cleanupCompleted;

  const ScopeEndedNotification({
    required this.scopeId,
    required this.scopeName,
    required this.duration,
    required this.cleanupCompleted,
  });
}
```

---

## Rebuild Groups

```dart
abstract class ScopeGroups {
  static const active = 'scope:active';
  static String byName(String name) => 'scope:name:$name';
  static String byId(String id) => 'scope:id:$id';
}
```

---

## Configuration

```dart
/// Configuration for ScopeBloc behavior.
@immutable
class ScopeBlocConfig {
  /// Default timeout for cleanup operations.
  /// Individual EndScopeEvent can override this.
  final Duration cleanupTimeout;

  /// Called when cleanup times out (for logging/metrics).
  final void Function(String scopeId, String scopeName)? onCleanupTimeout;

  const ScopeBlocConfig({
    this.cleanupTimeout = const Duration(seconds: 2),
    this.onCleanupTimeout,
  });
}
```

---

## ScopeBloc

```dart
class ScopeBloc extends JuiceBloc<ScopeState> {
  final ScopeBlocConfig config;

  /// Monotonic counter for deterministic, collision-free scope IDs.
  int _nextScopeId = 0;

  /// Generate a unique scope ID.
  /// Uses monotonic counter - deterministic and collision-free.
  String generateScopeId() => 'scope_${_nextScopeId++}';

  /// Notification stream for subscribers (separate from command bus)
  final _notifications = StreamController<ScopeNotification>.broadcast();
  Stream<ScopeNotification> get notifications => _notifications.stream;

  /// Publish a notification to subscribers
  void publish(ScopeNotification notification) {
    _notifications.add(notification);
  }

  /// In-flight end operations (for idempotency)
  final Map<String, Future<EndScopeResult>> _endingFutures = {};

  /// Get or create an ending future for idempotent scope end.
  /// Called by EndScopeUseCase to ensure concurrent end() calls
  /// return the same result.
  ///
  /// If [scopeId] already has an ending future, returns it.
  /// Otherwise, runs [work] and caches the result.
  Future<EndScopeResult> getOrCreateEndingFuture(
    String scopeId,
    Future<EndScopeResult> Function() work,
  ) async {
    // Already ending? Return existing future
    if (_endingFutures.containsKey(scopeId)) {
      return _endingFutures[scopeId]!;
    }

    // Start the end operation
    final completer = Completer<EndScopeResult>();
    _endingFutures[scopeId] = completer.future;

    try {
      final result = await work();
      completer.complete(result);
      return result;
    } catch (e, stack) {
      // Should never happen, but if it does, don't leave orphan future
      completer.completeError(e, stack);
      rethrow;
    } finally {
      _endingFutures.remove(scopeId);
    }
  }

  /// Get in-flight ending future for a scope, if any.
  /// Used when phase==ending to await existing operation.
  Future<EndScopeResult>? getEndingFuture(String scopeId) =>
      _endingFutures[scopeId];

  ScopeBloc({this.config = const ScopeBlocConfig()}) : super(const ScopeState()) {
    // Register use cases
    registerUseCase(StartScopeUseCase());
    registerUseCase(EndScopeUseCase());
  }

  @override
  Future<void> close() async {
    await _notifications.close();
    await super.close();
  }
}
```

---

## Use Cases

### StartScopeUseCase

```dart
class StartScopeUseCase extends BlocUseCase<ScopeBloc, StartScopeEvent> {
  @override
  Future<void> execute(StartScopeEvent event) async {
    // Generate unique ID via monotonic counter
    final scopeId = bloc.generateScopeId();

    final info = ScopeInfo(
      id: scopeId,
      name: event.name,
      phase: ScopePhase.active,
      startedAt: DateTime.now(),
      scope: event.scope,
    );

    emitUpdate(
      groupsToRebuild: {'scope:active', 'scope:name:${event.name}', 'scope:id:$scopeId'},
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
    event.complete(scopeId);
  }
}
```

### EndScopeUseCase

```dart
class EndScopeUseCase extends BlocUseCase<ScopeBloc, EndScopeEvent> {
  @override
  Future<void> execute(EndScopeEvent event) async {
    // Resolve scope
    final info = _resolveScope(event);
    if (info == null) {
      event.complete(EndScopeResult.notFound);
      return;
    }

    // Already ending? Await the in-flight operation instead of returning dummy.
    if (info.phase == ScopePhase.ending) {
      final inFlight = bloc.getEndingFuture(info.id);
      if (inFlight != null) {
        // Return the same result as the operation already in progress
        event.complete(await inFlight);
        return;
      }
      // Invariant breach: phase is ending but no future tracked.
      // Log and proceed safely - treat as already ended.
      assert(() {
        debugPrint('ScopeBloc: phase==ending but no in-flight future for ${info.id}');
        return true;
      }());
      event.complete(EndScopeResult.notFound);
      return;
    }

    // Idempotent: use getOrCreateEndingFuture to handle concurrent calls
    final result = await bloc.getOrCreateEndingFuture(
      info.id,
      () => _doEnd(info),
    );
    event.complete(result);
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
          .where((s) => s.name == event.scopeName && s.phase == ScopePhase.active)
          .firstOrNull;
    }
    return null;
  }

  Future<EndScopeResult> _doEnd(ScopeInfo info) async {
    // 1. Mark as ending
    emitUpdate(
      groupsToRebuild: {'scope:active', 'scope:name:${info.name}', 'scope:id:${info.id}'},
      newState: bloc.state.copyWith(
        scopes: {...bloc.state.scopes, info.id: info.copyWith(phase: ScopePhase.ending)},
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
      groupsToRebuild: {'scope:active', 'scope:name:${info.name}', 'scope:id:${info.id}'},
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
```

---

## Integration with FeatureScope

```dart
class FeatureScope {
  final String name;
  String? _scopeId;
  bool _started = false;

  /// Cached end future for true idempotency.
  /// All calls to end() return this same future.
  Future<EndScopeResult>? _endFuture;

  FeatureScope(this.name);

  /// Whether end() has been called
  bool get isEnding => _endFuture != null;

  /// Explicitly start the scope. Safe to call if ScopeBloc not registered.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Graceful degradation: if ScopeBloc not registered, scope still works
    // but without reactive lifecycle
    if (!BlocScope.isRegistered<ScopeBloc>()) {
      return;
    }

    final scopeBloc = BlocScope.get<ScopeBloc>();
    final event = StartScopeEvent(name: name, scope: this);
    scopeBloc.send(event);
    _scopeId = await event.result;
  }

  /// End this scope. Awaits cleanup completion.
  ///
  /// **Idempotent:** Multiple calls return the same future/result.
  Future<EndScopeResult> end() {
    // True idempotency: return cached future if already ending
    _endFuture ??= _doEnd();
    return _endFuture!;
  }

  Future<EndScopeResult> _doEnd() async {
    // Graceful degradation
    if (!BlocScope.isRegistered<ScopeBloc>()) {
      await BlocScope.endFeature(this);
      return const EndScopeResult(
        found: true,
        cleanupCompleted: true,
        cleanupFailedCount: 0,
        duration: Duration.zero,
        cleanupTaskCount: 0,
      );
    }

    final scopeBloc = BlocScope.get<ScopeBloc>();
    final event = EndScopeEvent(scopeId: _scopeId, scopeName: name);
    scopeBloc.send(event);
    return event.result;
  }

  /// Convenience: start and return self for chaining
  static Future<FeatureScope> create(String name) async {
    final scope = FeatureScope(name);
    await scope.start();
    return scope;
  }
}
```

---

## Subscriber Pattern

How other blocs subscribe to scope notifications:

```dart
class FetchBloc extends JuiceBloc<FetchState> {
  StreamSubscription? _scopeSubscription;

  FetchBloc() : super(FetchState.initial()) {
    _subscribeToScopes();
  }

  void _subscribeToScopes() {
    // Graceful: only subscribe if ScopeBloc exists
    if (!BlocScope.isRegistered<ScopeBloc>()) return;

    final scopeBloc = BlocScope.get<ScopeBloc>();
    _scopeSubscription = scopeBloc.notifications
        .whereType<ScopeEndingNotification>()
        .listen(_onScopeEnding);
  }

  void _onScopeEnding(ScopeEndingNotification notification) {
    // Register cleanup on the barrier
    notification.barrier.add(_cancelRequestsForScope(notification.scopeName));
  }

  Future<void> _cancelRequestsForScope(String scopeName) async {
    final toCancel = state.activeRequests.values
        .where((r) => r.scope == scopeName)
        .toList();

    for (final request in toCancel) {
      request.cancelToken?.cancel();
    }

    // Wait for cancellation to propagate
    await Future.delayed(const Duration(milliseconds: 10));
  }

  @override
  Future<void> close() async {
    await _scopeSubscription?.cancel();
    await super.close();
  }
}
```

---

## Registration

```dart
void main() {
  // Register ScopeBloc first (permanent)
  BlocScope.register<ScopeBloc>(
    () => ScopeBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  // Other blocs can now subscribe to scope lifecycle
  BlocScope.register<FetchBloc>(
    () => FetchBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(MyApp());
}
```

---

## File Structure

```
packages/juice/lib/src/bloc/src/
├── lifecycle/
│   ├── feature_scope.dart       # Existing (modified)
│   ├── bloc_scope.dart          # Existing
│   ├── scope_bloc.dart          # NEW
│   ├── scope_state.dart         # NEW
│   ├── scope_events.dart        # NEW
│   └── cleanup_barrier.dart     # NEW
```

---

## API Summary

| Type | Name | Purpose |
|------|------|---------|
| Bloc | `ScopeBloc` | Permanent, tracks scopes, publishes lifecycle |
| Config | `ScopeBlocConfig` | Configurable timeout and callbacks |
| State | `ScopeState` | Active scopes by ID |
| Class | `ScopeInfo` | Scope metadata (id, name, phase, startedAt) |
| Class | `CleanupBarrier` | Collects cleanup futures, awaits with timeout |
| Class | `CleanupBarrierResult` | Result with completed, timedOut, failedCount |
| Enum | `ScopePhase` | `active`, `ending` |
| Event | `StartScopeEvent` | Begin tracking (returns scopeId) |
| Event | `EndScopeEvent` | End scope (returns EndScopeResult) |
| Abstract | `ScopeNotification` | Base class for typed notifications |
| Notification | `ScopeStartedNotification` | Scope started |
| Notification | `ScopeEndingNotification` | Cleanup now! (has barrier) |
| Notification | `ScopeEndedNotification` | Disposal complete |
| Groups | `scope:active`, `scope:name:{n}`, `scope:id:{id}` | Rebuild groups |

---

## Guarantees

1. **Deterministic cleanup order:** Ending published → barrier awaited → blocs disposed
2. **Timeout protection:** Cleanup has configurable timeout (default 2s), won't hang forever
3. **Disposal always proceeds:** Timeout only affects `cleanupCompleted` flag; blocs are **always** disposed after timeout. This prevents the app from hanging indefinitely.
4. **Error resilience:** Individual cleanup task failures are logged but don't abort disposal
5. **Idempotent end:** Multiple `end()` calls return the **same future** (not just same result)
6. **Concurrent safety:** In-flight ends are tracked via `getOrCreateEndingFuture()`, no double-dispose
7. **Phase consistency:** If `phase==ending`, await the in-flight future instead of returning dummy result
8. **Graceful degradation:** FeatureScope works without ScopeBloc (just no reactive cleanup)
9. **Deterministic IDs:** Scope IDs use monotonic counter (collision-free, deterministic in tests)
10. **Late registration safety:** `barrier.add()` after close returns `false` instead of throwing
11. **Type-safe notifications:** All notifications extend `ScopeNotification` for safe `.whereType<T>()` filtering

---

## Migration

Existing code continues to work:

```dart
// Before (still works, just no reactive cleanup)
final scope = FeatureScope('checkout');
await scope.end();

// After (explicit start for reactive cleanup)
final scope = FeatureScope('checkout');
await scope.start();  // NEW: explicit start
// ... use scope ...
await scope.end();    // Now FetchBloc etc. can cleanup

// Or use factory
final scope = await FeatureScope.create('checkout');
```

---

## Spec Version

| Version | Status | Changes |
|---------|--------|---------|
| 0.1 | Draft | Initial concept |
| 1.0 | Draft | Added CleanupBarrier, scopeId, publish/send separation, idempotency, graceful degradation |
| 1.1 | Draft | Fixed: CleanupBarrier error handling (returns `CleanupBarrierResult`), `add()` returns bool, true idempotent `end()` via cached future, `getOrCreateEndingFuture()` for Dart privacy |
| 1.2 | Freeze candidate | Monotonic counter IDs, `ScopeBlocConfig` for configurable timeout, typed `ScopeNotification` base class, phase==ending awaits in-flight future, explicit scopeName ambiguity docs, "disposal always proceeds" guarantee |
