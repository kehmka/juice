# CleanupBarrier - Design Document

This document describes the CleanupBarrier pattern for deterministic async cleanup during scope lifecycle transitions.

## Problem Statement

When a `FeatureScope` ends, multiple blocs may need to perform async cleanup:

- `FetchBloc` cancels in-flight HTTP requests
- `AuthBloc` persists session state
- `WebSocketBloc` sends disconnect messages
- `CacheBloc` flushes pending writes

**The challenge:** How does the scope coordinator know when all cleanup is complete before disposing blocs?

### Failed Approaches

**Approach 1: Fixed Delay**
```dart
// DON'T DO THIS
publish(ScopeEndingNotification());
await Future.delayed(Duration(milliseconds: 50)); // Hope everyone finished
disposeBlocs();
```

Problems:
- 50ms may be too short for slow operations
- 50ms is wasted time for fast operations
- No guarantee cleanup actually completed
- Silent failures when cleanup exceeds timeout

**Approach 2: Subscribers Return Futures**
```dart
// Can't work - subscriptions are fire-and-forget
bloc.stream.listen((event) async {
  await cleanup(); // Caller can't await this
});
```

Problem: Stream subscriptions don't return values to publishers.

---

## Solution: CleanupBarrier

The CleanupBarrier pattern inverts control: instead of the coordinator waiting for subscribers, **subscribers register their cleanup futures on a barrier object** that the coordinator owns.

### The Pattern

```
┌──────────────────────────────────────────────────────────────────┐
│                        CLEANUP TIMELINE                          │
├──────────────────────────────────────────────────────────────────┤
│ t=0ms   ScopeBloc: barrier = CleanupBarrier()                    │
│ t=0ms   ScopeBloc: publish(ScopeEndingNotification(barrier))     │
│ t=0ms   FetchBloc: barrier.add(cancelRequests())     ← sync      │
│ t=0ms   AuthBloc:  barrier.add(saveSession())        ← sync      │
│ t=0ms   CacheBloc: barrier.add(flushWrites())        ← sync      │
│ t=0ms   ScopeBloc: await barrier.wait()              ← blocks    │
│         ┌─────────────────────────────────────────────────────┐  │
│         │ Barrier: Future.wait([future1, future2, future3])   │  │
│         │          .timeout(Duration(seconds: 2))             │  │
│         └─────────────────────────────────────────────────────┘  │
│ t=50ms  FetchBloc cleanup completes                              │
│ t=80ms  AuthBloc cleanup completes                               │
│ t=120ms CacheBloc cleanup completes                              │
│ t=120ms Barrier: returns true (all cleanup succeeded)            │
│ t=120ms ScopeBloc: dispose blocs safely                          │
└──────────────────────────────────────────────────────────────────┘
```

### Why Synchronous Registration Matters

The barrier is passed **inside** the notification. Subscribers must register their cleanup futures **synchronously** in their event handler:

```dart
void _onScopeEnding(ScopeEndingNotification notification) {
  // SYNC: Register the future immediately
  notification.barrier.add(_cancelAllRequests());

  // DON'T do async work before adding to barrier
  // await someAsyncCheck(); // TOO LATE - barrier may already be closed!
  // notification.barrier.add(cleanup);
}
```

This is critical because:
1. `ScopeBloc` publishes the notification
2. All subscribers receive it synchronously (Dart event loop)
3. Each subscriber synchronously adds their cleanup future
4. **Then** `ScopeBloc` calls `barrier.wait()` which closes the barrier

If a subscriber does async work before calling `barrier.add()`, the barrier may already be closed by the time they try to register.

---

## Implementation

### CleanupBarrierResult

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
```

### CleanupBarrier Class

```dart
/// Collects cleanup futures from multiple subscribers and awaits them
/// with a timeout.
class CleanupBarrier {
  final List<Future<void>> _futures = [];
  bool _closed = false;
  int _failedCount = 0;

  /// Add a cleanup future to the barrier.
  ///
  /// Must be called synchronously when receiving [ScopeEndingNotification].
  ///
  /// Returns `true` if added successfully.
  /// Returns `false` if barrier already closed (does NOT throw).
  bool add(Future<void> cleanup) {
    if (_closed) {
      // Log but don't crash - late registration is a bug but shouldn't
      // bring down the app during scope shutdown
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

  /// Wait for all registered cleanup futures to complete.
  ///
  /// Individual task failures are caught and counted, NOT propagated.
  /// This ensures scope disposal always completes deterministically.
  ///
  /// Once called, the barrier is closed and no more futures can be added.
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
        // Log but don't propagate - other cleanup must continue
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

  /// Number of cleanup futures registered.
  int get count => _futures.length;
}
```

### ScopeEndingNotification

```dart
/// Notification published when a scope is about to end.
///
/// Subscribers should add their cleanup futures to [barrier] synchronously.
@immutable
class ScopeEndingNotification extends EventBase {
  /// The name of the scope that is ending.
  final String scopeName;

  /// The unique ID of the scope instance.
  final String scopeId;

  /// The barrier for registering cleanup futures.
  ///
  /// Call `barrier.add(yourCleanupFuture)` synchronously when receiving
  /// this notification.
  final CleanupBarrier barrier;

  const ScopeEndingNotification({
    required this.scopeName,
    required this.scopeId,
    required this.barrier,
  });
}
```

### Publisher (ScopeBloc)

```dart
class EndScopeUseCase extends BlocUseCase<ScopeBloc, EndScopeEvent>
    with ResultEvent<EndScopeResult> {

  @override
  Future<void> execute(EndScopeEvent event) async {
    final scopeInfo = bloc.state.activeScopes[event.scopeId];
    if (scopeInfo == null) {
      event.complete(EndScopeResult.notFound);
      return;
    }

    // 1. Create the barrier
    final barrier = CleanupBarrier();

    // 2. Transition to ending phase
    emitUpdate(
      newState: bloc.state.withScopePhase(event.scopeId, ScopePhase.ending),
      groupsToRebuild: {'scope:${scopeInfo.name}'},
    );

    // 3. Publish notification with barrier
    //    Subscribers will synchronously add their cleanup futures
    bloc.publish(ScopeEndingNotification(
      scopeName: scopeInfo.name,
      scopeId: event.scopeId,
      barrier: barrier,
    ));

    // 4. Wait for all cleanup to complete (or timeout)
    // Note: wait() catches individual task errors - never throws
    final result = await barrier.wait(
      timeout: event.cleanupTimeout ?? const Duration(seconds: 2),
    );

    if (result.timedOut) {
      log('Scope ${scopeInfo.name} cleanup timed out - proceeding anyway');
    }
    if (result.failedCount > 0) {
      log('Scope ${scopeInfo.name}: ${result.failedCount}/${result.taskCount} '
          'cleanup tasks failed');
    }

    // 5. Now safe to dispose blocs
    await scopeInfo.scope.end();

    // 6. Emit final state and complete
    emitUpdate(
      newState: bloc.state.withScopeRemoved(event.scopeId),
      groupsToRebuild: {'scopes'},
    );

    event.complete(EndScopeResult.success);
  }
}
```

### Subscriber (FetchBloc)

```dart
class FetchBloc extends JuiceBloc<FetchState> {
  FetchBloc() : super(
    FetchState.initial(),
    [
      // Use case builders...
      () => EventSubscription<ScopeBloc, ScopeEndingNotification, _CleanupEvent>(
        transform: (notification) => _CleanupEvent(notification.barrier),
      ),
    ],
    [],
  );
}

class _CleanupEvent extends EventBase {
  final CleanupBarrier barrier;
  _CleanupEvent(this.barrier);
}

class _CleanupUseCase extends BlocUseCase<FetchBloc, _CleanupEvent> {
  @override
  Future<void> execute(_CleanupEvent event) async {
    // Register cleanup SYNCHRONOUSLY
    event.barrier.add(_performCleanup());
  }

  Future<void> _performCleanup() async {
    // Cancel all in-flight requests
    for (final request in bloc.state.activeRequests.values) {
      request.cancel();
    }

    // Wait for cancellations to complete
    await Future.wait(
      bloc.state.activeRequests.values.map((r) => r.whenComplete),
    );
  }
}
```

---

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SEQUENCE DIAGRAM                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  User Code          ScopeBloc              FetchBloc           AuthBloc     │
│      │                  │                      │                   │        │
│      │  EndScopeEvent   │                      │                   │        │
│      │─────────────────>│                      │                   │        │
│      │                  │                      │                   │        │
│      │                  │ barrier = CleanupBarrier()               │        │
│      │                  │                      │                   │        │
│      │                  │ publish(ScopeEndingNotification)         │        │
│      │                  │─────────────────────>│                   │        │
│      │                  │─────────────────────────────────────────>│        │
│      │                  │                      │                   │        │
│      │                  │    barrier.add(f1)   │                   │        │
│      │                  │<─────────────────────│                   │        │
│      │                  │                      │  barrier.add(f2)  │        │
│      │                  │<─────────────────────────────────────────│        │
│      │                  │                      │                   │        │
│      │                  │ await barrier.wait()                     │        │
│      │                  │─────────┐            │                   │        │
│      │                  │         │ Future.wait([f1, f2])          │        │
│      │                  │         │ .timeout(2s)                   │        │
│      │                  │<────────┘            │                   │        │
│      │                  │                      │                   │        │
│      │                  │ dispose blocs        │                   │        │
│      │                  │─────────────────────>│ close()           │        │
│      │                  │─────────────────────────────────────────>│ close()│
│      │                  │                      │                   │        │
│      │  EndScopeResult  │                      │                   │        │
│      │<─────────────────│                      │                   │        │
│      │                  │                      │                   │        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Guarantees

### 1. Deterministic Cleanup Order

The barrier ensures all cleanup futures are collected **before** waiting begins:

```dart
// This order is guaranteed:
publish(notification);        // Step 1: All subscribers notified
await barrier.wait();         // Step 2: Wait for ALL their cleanup
disposeBlocs();               // Step 3: Safe to dispose
```

### 2. Timeout Protection

Cleanup operations have a bounded wait time:

```dart
final result = await barrier.wait(timeout: Duration(seconds: 2));
if (result.timedOut) {
  // Some cleanup timed out - log and proceed
  // The scope must end eventually
}
```

### 3. Error Resilience

Individual cleanup task failures don't abort the barrier:

```dart
barrier.add(Future.error('task1 failed'));  // Will be caught
barrier.add(successfulCleanup());           // Still runs
final result = await barrier.wait();
// result.failedCount == 1, but wait() did NOT throw
// Scope disposal continues deterministically
```

### 4. Late Registration Safety

Once `wait()` is called, no more futures can be added - but it returns `false` instead of throwing:

```dart
barrier.add(cleanup1);        // OK, returns true
await barrier.wait();         // Closes barrier
barrier.add(cleanup2);        // Returns false (does NOT throw)
```

This prevents crashes during scope shutdown when a subscriber accidentally awaits before adding.

### 5. Empty Barrier Fast Path

If no subscribers register cleanup:

```dart
await barrier.wait();  // Returns immediately with completed=true
```

---

## When to Use CleanupBarrier

| Scenario | Use CleanupBarrier? |
|----------|---------------------|
| Canceling in-flight HTTP requests | Yes |
| Persisting unsaved state | Yes |
| Closing WebSocket connections gracefully | Yes |
| Flushing cache/database writes | Yes |
| Simple state reset (sync) | No - just do it directly |
| Cleanup with no external dependencies | No - just do it directly |

---

## Error Handling

**The barrier handles errors automatically** - you don't need try/catch in your cleanup:

```dart
Future<void> _performCleanup() async {
  // If this throws, CleanupBarrier catches it and increments failedCount
  // Other cleanup tasks continue running
  await cancelRequests();
}
```

However, if you want to handle errors yourself for logging purposes:

```dart
Future<void> _performCleanup() async {
  try {
    await cancelRequests();
  } catch (e) {
    log('Request cancellation failed: $e');
    // Rethrow is optional - barrier will catch either way
    rethrow;
  }
}
```

The barrier wraps each future individually, so one failure never aborts other tasks:

```dart
// All three run to completion (or timeout), regardless of individual failures
barrier.add(taskThatThrows());
barrier.add(taskThatSucceeds());
barrier.add(taskThatTimesOut());

final result = await barrier.wait();
// result.failedCount == 1 (the throw)
// result.completed == false (if taskThatTimesOut hit the timeout)
```

---

## Testing

```dart
test('CleanupBarrier collects and awaits futures', () async {
  final barrier = CleanupBarrier();
  var cleanup1Done = false;
  var cleanup2Done = false;

  // Simulate subscribers adding cleanup
  expect(barrier.add(Future.delayed(Duration(milliseconds: 50), () {
    cleanup1Done = true;
  })), isTrue);
  expect(barrier.add(Future.delayed(Duration(milliseconds: 100), () {
    cleanup2Done = true;
  })), isTrue);

  expect(barrier.count, 2);

  final result = await barrier.wait();

  expect(result.completed, isTrue);
  expect(result.timedOut, isFalse);
  expect(result.failedCount, 0);
  expect(result.taskCount, 2);
  expect(cleanup1Done, isTrue);
  expect(cleanup2Done, isTrue);
});

test('CleanupBarrier times out gracefully', () async {
  final barrier = CleanupBarrier();

  barrier.add(Future.delayed(Duration(seconds: 10)));

  final result = await barrier.wait(timeout: Duration(milliseconds: 50));

  expect(result.completed, isFalse);
  expect(result.timedOut, isTrue);
});

test('CleanupBarrier catches individual task errors', () async {
  final barrier = CleanupBarrier();

  barrier.add(Future.error('task failed'));
  barrier.add(Future.value()); // This still runs

  final result = await barrier.wait();

  expect(result.completed, isTrue);  // Completed, just with errors
  expect(result.failedCount, 1);
  expect(result.taskCount, 2);
});

test('CleanupBarrier returns false on late add', () async {
  final barrier = CleanupBarrier();
  await barrier.wait(); // Close the barrier

  // Does NOT throw - returns false
  expect(barrier.add(Future.value()), isFalse);
});

test('CleanupBarrier empty fast path', () async {
  final barrier = CleanupBarrier();
  final result = await barrier.wait();

  expect(result.completed, isTrue);
  expect(result.taskCount, 0);
});
```

---

## Summary

CleanupBarrier solves the async cleanup coordination problem by:

1. **Inverting control** - Subscribers register futures, not the coordinator
2. **Synchronous registration** - Futures must be added before `wait()` is called
3. **Bounded waiting** - Timeout prevents indefinite hangs
4. **Error resilience** - Individual task failures are caught and counted, not propagated
5. **Late registration safety** - `add()` returns `false` after close, never throws
6. **Structured results** - `CleanupBarrierResult` provides `completed`, `timedOut`, `failedCount`, `taskCount`

This pattern ensures deterministic cleanup ordering while respecting the fire-and-forget nature of event subscriptions.

## Related

- [Bloc Lifecycle Management](bloc-lifecycle-management.md) - FeatureScope and lease patterns
- [ScopeBloc Specification](../../packages/juice/doc/SCOPE_BLOC_SPEC.md) - Full ScopeBloc design
