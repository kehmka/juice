# Juice Framework - Known Issues

This document tracks known issues, bugs, and areas for improvement in the Juice framework codebase.

---

## Critical Issues

### 1. ~~Invalid `dispose()` Method Signature~~ FIXED

**File:** `lib/src/bloc/src/juice_bloc.dart`, Lines 209-211

**Status:** Fixed - Changed to synchronous `void dispose() { close(); }`

---

### 2. ~~Unawaited Async Calls in Resource Cleanup~~ FIXED

**File:** `lib/src/bloc/src/bloc_scope.dart`, Lines 109, 128, 140, 152, 160

**Status:** Fixed - All calls now use `close()` (fire-and-forget pattern).

---

### 3. ~~BlocScope Calls `dispose()` Instead of `close()`~~ FIXED

**File:** `lib/src/bloc/src/bloc_scope.dart`

**Status:** Fixed - All `dispose()` calls replaced with `close()` calls.

---

## Medium Issues

### 4. ~~Unsafe Type Cast to Dynamic~~ FIXED

**File:** `lib/src/bloc/src/core/use_case_executor.dart`

**Status:** Fixed - Added `setBloc(JuiceBloc blocInstance)` method to UseCase class. The executor now calls `useCase.setBloc(context.bloc as JuiceBloc)` instead of `(useCase as dynamic).bloc = context.bloc`. The cast is now contained within the UseCase class with proper type safety.

---

### 5. ~~Race Condition in EventSubscription Initialization~~ FIXED

**File:** `lib/src/bloc/src/use_case_builders/src/event_subscription.dart`

**Status:** Fixed - Added `_isClosed` guard at start of `_initialize()` to prevent race condition when `close()` is called before the deferred microtask executes. Also fixed in `RelayUseCaseBuilder`.

---

### 6. ~~Forced Non-Null Access Without Safety Checks~~ FIXED

**File:** `lib/src/ui/src/widget_support.dart`

**Status:** Fixed - Replaced forced non-null access with safe null-coalescing pattern:
```dart
final groups = event?.groupsToRebuild;
if (groups == null || groups.isEmpty) return false;
```

---

### 7. ~~Inconsistent Default Groups in StatelessJuiceWidget Variants~~ FIXED

**File:** `lib/src/ui/src/stateless_juice_widget.dart`

**Status:** Fixed - Standardized all widget variants to use `groups = const {"*"}` as default:
- `StatelessJuiceWidget`: `{"*"}` (unchanged)
- `StatelessJuiceWidget2`: `{"*"}` (was `{}`)
- `StatelessJuiceWidget3`: `{"*"}` (unchanged)

All variants now consistently rebuild on all state changes by default.

---

### 8. ~~Unchecked Late Variable Access~~ PARTIALLY FIXED

**File:** `lib/src/bloc/src/use_case_builders/src/relay_use_case_builder.dart`, Lines 60-63

**Status:** Partially Fixed - The BlocLease system now provides:
- try-catch wrapper that throws explicit `StateError` on initialization failure
- Closed bloc checks before proceeding (`if (sourceBloc.isClosed || destBloc.isClosed)`)
- Proper lease cleanup in `close()` method
- Race condition guard (`if (_isClosed) return;`)

The `late` variables are still used but initialization failures now produce clear errors rather than cryptic "Late variable not initialized" crashes.

**Remaining:** Could convert to nullable types for full safety, but current implementation is acceptable.

---

## Low Priority Issues

### 9. Missing Exception Context in Error Logging

**File:** `lib/src/bloc/src/use_case_builders/src/relay_use_case_builder.dart`, Lines 124-126

**Description:** Error logging doesn't include which source and destination blocs are involved in the relay, making debugging difficult in applications with multiple relays.

```dart
} catch (e, stackTrace) {
  JuiceLoggerConfig.logger.logError('Error in relay', e, stackTrace);
  await close();  // Closes without context about which relay failed
}
```

**Impact:** Low - Poor observability, but functionality works.

**Fix:** Add bloc type information to error context:
```dart
JuiceLoggerConfig.logger.logError('Error in relay', e, stackTrace, context: {
  'sourceBloc': TSourceBloc.toString(),
  'destBloc': TDestBloc.toString(),
});
```

---

### 10. Silent Event Swallowing in EventDispatcher

**File:** `lib/src/bloc/src/core/event_dispatcher.dart`, Line 76

**Description:** When `_onUnhandledEvent` is provided, unhandled events are silently processed without any error indication. This can mask configuration issues where events aren't properly registered.

```dart
if (_onUnhandledEvent != null) {
  _onUnhandledEvent(event);
  return;  // Returns without error, silently swallows event
}
```

**Impact:** Low - Silent failures make debugging difficult.

**Fix:** Consider logging a warning even when handler is provided.

---

### 11. Unused `disposeAll()` Method

**File:** `lib/src/bloc/src/bloc_dependency_resolver.dart`, Line 17

**Description:** Base class has empty `disposeAll()` that's never called. `BlocResolver` and `CompositeResolver` implement it but `JuiceBloc` doesn't use it.

```dart
void disposeAll() {}
```

**Impact:** Low - Unused API, potential dead code.

**Fix:** Either integrate into bloc lifecycle or remove.

---

### 12. Verbose Inline Error Throwing Pattern

**File:** `lib/src/bloc/src/juice_async_builder.dart`, Lines 99-100, 117-118, 144-145, 203-204

**Description:** Multiple lines throw errors inline without option for null coalescing. Pattern is verbose and error-prone.

```dart
widget.initial ?? (throw ArgumentError("widget.initial must not be null"))
```

**Impact:** Low - Code maintainability concern.

**Fix:** Consider using a helper function or extracting to clearer error handling.

---

### 13. Ambiguous `_Disposable` Interface

**File:** `lib/src/bloc/src/juice_bloc.dart`, Lines 21-23

**Description:** Implements private interface but method is async-unsafe. Also conflicts semantically with the actual async `close()` method.

```dart
abstract class _Disposable {
  void dispose();
}
```

**Impact:** Low - Interface confusion, poor API design.

**Fix:** Either remove the interface (it's private anyway) or align with Flutter's actual `Disposable` patterns.

---

### 14. UseCase Emit Functions Lack Event Context

**File:** `lib/src/bloc/src/usecase.dart`, Lines 50-87

**Description:** Emit functions have no context about the triggering event for debugging/logging purposes.

```dart
late void Function({BlocState? newState, ...}) emitUpdate;
// No way to know which event triggered this emit
```

**Impact:** Low - Observability issue when debugging complex state flows.

**Fix:** Consider adding optional event context to emit functions.

---

## Test Coverage Gaps

### 15. Missing Resource Cleanup Tests

**Files Affected:**
- `lib/src/bloc/src/juice_bloc.dart`
- `lib/src/bloc/src/bloc_scope.dart`

**Missing Tests:**
- Verify all resources are cleaned up when bloc closes
- Test that stream subscriptions are cancelled
- Test that nested blocs are properly disposed

---

### 16. Missing EventSubscription Tests

**File:** `lib/src/bloc/src/use_case_builders/src/event_subscription.dart`

**Missing Tests:**
- Initialization/closure race conditions
- Behavior when source bloc is closed before subscription initializes
- Error handling when `toEvent` transformer throws
- Multiple subscriptions to same source event

---

### 17. Missing RelayUseCaseBuilder Error Tests

**File:** `lib/src/bloc/src/use_case_builders/src/relay_use_case_builder.dart`

**Missing Tests:**
- Behavior when source bloc closes mid-relay
- Error propagation from transformer function
- Recovery behavior after errors

---

### 18. Missing BlocScope Eviction Tests

**File:** `lib/src/bloc/src/bloc_scope.dart`

**Missing Tests:**
- LRU eviction behavior
- Resource cleanup on eviction
- Behavior when evicted bloc is still in use by widgets

---

## Documentation Gaps

### 19. Missing Late Variable Documentation

**Description:** Multiple `late` variables throughout codebase lack documentation about when they're initialized and the risks of accessing them before initialization.

**Files Affected:**
- `lib/src/bloc/src/use_case_builders/src/relay_use_case_builder.dart`
- `lib/src/bloc/src/use_case_builders/src/event_subscription.dart`

---

### 20. Missing Error Recovery Documentation

**Description:** No documentation on how to handle failures in:
- EventSubscription (what happens when source bloc closes?)
- RelayUseCaseBuilder (how to recover from relay errors?)
- BlocScope (what happens when resolution fails?)

---

### 21. Missing Lifecycle Documentation

**Description:** The relationship between `dispose()` and `close()` is not documented. Developers may not know which to call or when.

---

## Summary

| Priority | Count | Status |
|----------|-------|--------|
| Critical | 3 | All Fixed (#1-3) |
| Medium | 5 | All Fixed (#4-7, #8 partial) |
| Low | 6 | Open |
| Tests | 4 | Open |
| Docs | 3 | Open |
| **Total** | **21** | **8 Fixed, 13 Open** |

---

## Fix Priority Recommendation

1. ~~**First:** Fix critical issues #1-3 (dispose/close cleanup)~~ DONE
2. ~~**Second:** Fix race conditions #5, #8~~ DONE
3. ~~**Third:** Fix remaining medium issues #4, #6, #7 (type safety, inconsistencies)~~ DONE
4. **Next:** Add missing tests #15-18
5. **Finally:** Address low priority and documentation issues
