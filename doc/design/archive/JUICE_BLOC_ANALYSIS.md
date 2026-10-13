# JuiceBloc Architecture Analysis

This document provides a detailed technical analysis of the `JuiceBloc` class, the core component of the Juice framework.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Class Hierarchy](#class-hierarchy)
3. [Component Breakdown](#component-breakdown)
4. [Code Analysis](#code-analysis)
5. [Pros and Cons](#pros-and-cons)
6. [Refactoring Recommendations](#refactoring-recommendations)
7. [Metrics](#metrics)

---

## Architecture Overview

`JuiceBloc` is the base class for all blocs in the Juice framework. It extends the core `Bloc` class and adds:

- **Use Case Pattern**: Business logic extracted into dedicated classes
- **StreamStatus Wrapper**: State emissions include operation metadata
- **Rebuild Groups**: Fine-grained widget rebuild control
- **Aviators**: Built-in navigation coordination
- **Structured Logging**: Comprehensive operation logging

### Data Flow

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌────────────┐
│   Widget    │────▶│   JuiceBloc  │────▶│   UseCase   │────▶│   State    │
│  send(Event)│     │  _register() │     │  execute()  │     │  Emission  │
└─────────────┘     └──────────────┘     └─────────────┘     └────────────┘
                           │                    │                   │
                           ▼                    ▼                   ▼
                    ┌──────────────┐     ┌─────────────┐     ┌────────────┐
                    │   Handler    │     │ emitUpdate  │     │StreamStatus│
                    │   Lookup     │     │ emitWaiting │     │  .updating │
                    │              │     │ emitFailure │     │  .waiting  │
                    │              │     │ emitCancel  │     │  .failure  │
                    └──────────────┘     └─────────────┘     └────────────┘
                                                                    │
                                                                    ▼
                                                             ┌────────────┐
                                                             │  Widgets   │
                                                             │  Rebuild   │
                                                             │ (by group) │
                                                             └────────────┘
```

---

## Class Hierarchy

```
┌─────────────────────────────────────────────────────────────────────┐
│                         JuiceBloc<TState>                           │
│                                                                     │
│  Responsibilities:                                                  │
│  - Use case registration and lifecycle                              │
│  - Emit function injection into use cases                           │
│  - Aviator (navigation) management                                  │
│  - Logging coordination                                             │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │              Bloc<EventBase, StreamStatus<TState>>            │  │
│  │                                                               │  │
│  │  Responsibilities:                                            │  │
│  │  - Event handler registration                                 │  │
│  │  - Event routing to handlers                                  │  │
│  │  - Emitter lifecycle management                               │  │
│  │                                                               │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │                   BlocBase<State>                       │  │  │
│  │  │                                                         │  │  │
│  │  │  Responsibilities:                                      │  │  │
│  │  │  - Stream management (StreamController)                 │  │  │
│  │  │  - State storage and emission                           │  │  │
│  │  │  - Closed state tracking                                │  │  │
│  │  │                                                         │  │  │
│  │  │  Key Members:                                           │  │  │
│  │  │  - _stateController: StreamController<State>            │  │  │
│  │  │  - _state: State                                        │  │  │
│  │  │  - stream: Stream<State>                                │  │  │
│  │  │  - currentStatus: State                                 │  │  │
│  │  │  - isClosed: bool                                       │  │  │
│  │  │  - emit(State): void                                    │  │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  │                                                               │  │
│  │  Key Members:                                                 │  │
│  │  - _eventController: StreamController<Event>                  │  │
│  │  - _handlers: List<_Handler>                                  │  │
│  │  - _emitters: List<_Emitter>                                  │  │
│  │  - register<E>(handler, eventType): void                      │  │
│  │  - send(Event): Future<void>                                  │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  Key Members:                                                       │
│  - _builders: List<UseCaseBuilderBase>                              │
│  - _aviators: Map<String, AviatorBase>                              │
│  - logger: JuiceLogger                                              │
│  - state: TState (accessor)                                         │
│  - oldState: TState (accessor)                                      │
│  - _register(UseCaseBuilderBase): void                              │
│  - start(): void                                                    │
│  - close(): Future<void>                                            │
└─────────────────────────────────────────────────────────────────────┘
```

### Interfaces Implemented

| Interface | Purpose |
|-----------|---------|
| `StateStreamable<StreamStatus<TState>>` | Provides stream of states |
| `Emittable<StreamStatus<TState>>` | Allows state emission |
| `ErrorSink` | Error handling destination |
| `Closable` | Resource cleanup contract |
| `_Disposable` | Internal disposal contract |

---

## Component Breakdown

### 1. Constructor

```dart
JuiceBloc(
  TState initialState,
  List<UseCaseBuilderGenerator> useCases,
  List<AviatorBuilder> aviatorBuilders, {
  JuiceLogger? customLogger,
  super.errorHandler = const BlocErrorHandler(),
})
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `initialState` | `TState` | Yes | Starting state for the bloc |
| `useCases` | `List<UseCaseBuilderGenerator>` | Yes | Factory functions that create use case builders |
| `aviatorBuilders` | `List<AviatorBuilder>` | Yes | Factory functions that create navigation handlers |
| `customLogger` | `JuiceLogger?` | No | Override the default logger |
| `errorHandler` | `BlocErrorHandler` | No | Custom error handling strategy |

**Type Definitions:**

```dart
typedef UseCaseBuilderGenerator = UseCaseBuilderBase Function();
typedef AviatorBuilder = AviatorBase Function();
```

### 2. State Accessors

```dart
TState get state => currentStatus.state;
TState get oldState => currentStatus.oldState;
```

| Accessor | Returns | Description |
|----------|---------|-------------|
| `state` | `TState` | Current state unwrapped from `StreamStatus` |
| `oldState` | `TState` | Previous state for comparison/diffing |
| `currentStatus` | `StreamStatus<TState>` | Full status with metadata (inherited) |

### 3. Use Case Registration

The `_register` method is the core of JuiceBloc, responsible for:

1. **Handler Registration**: Connecting event types to use case handlers
2. **Emit Function Creation**: Building the emit functions for use cases
3. **Use Case Wiring**: Injecting dependencies into use case instances
4. **Initial Event Dispatch**: Firing startup events if configured

```dart
void _register<TEvent extends EventBase>(UseCaseBuilderBase builder) {
  Type eventType = builder.eventType;
  UseCaseGenerator handler = builder.generator;

  register<TEvent>((event, emit) async {
    // 1. Define emit functions (emitUpdate, emitWaiting, emitFailure, emitCancel)
    // 2. Create use case instance
    // 3. Wire emit functions to use case
    // 4. Execute use case
  }, eventType);

  // 5. Dispatch initial event if configured
}
```

### 4. Emit Functions

Four emit functions are created for each registered use case:

| Function | StreamStatus | Purpose |
|----------|--------------|---------|
| `emitUpdate` | `UpdatingStatus` | Normal state transition |
| `emitWaiting` | `WaitingStatus` | Async operation in progress |
| `emitFailure` | `FailureStatus` | Error occurred |
| `emitCancel` | `CancelingStatus` | Operation cancelled |

**Common Parameters:**

```dart
void emitXxx({
  TState? newState,           // New state (optional, defaults to current)
  String? aviatorName,        // Navigation target
  Map<String, dynamic>? aviatorArgs,  // Navigation arguments
  Set<String>? groupsToRebuild,       // Widget groups to rebuild
})
```

### 5. Built-in Use Cases

```dart
void _registerBuiltInUseCases() {
  _register(UseCaseBuilder(
    typeOfEvent: UpdateEvent,
    useCaseGenerator: () => UpdateUseCase(),
  ));
  _register(UseCaseBuilder(
    typeOfEvent: UpdateEvent<TState>,
    useCaseGenerator: () => UpdateUseCase(),
  ));
}
```

`UpdateEvent` allows direct state updates without a custom use case:

```dart
bloc.send(UpdateEvent(
  newState: newState,
  groupsToRebuild: {"my_group"},
));
```

### 6. Error Handling

```dart
@override
void onError(Object error, StackTrace stackTrace) {
  // 1. Log the error with context
  logger.logError('Unhandled bloc error', error, stackTrace, context: {
    'type': 'bloc_error',
    'bloc': runtimeType.toString(),
    'state': state.toString()
  });

  // 2. Delegate to custom error handler (with safety catch)
  try {
    errorHandler.handleError(...);
  } catch (e, handlerStackTrace) {
    logger.logError('Error in custom errorHandler', ...);
  }

  // 3. Log current state for debugging
  logger.log('Current state during error', ...);

  // 4. Call parent handler
  super.onError(error, stackTrace);
}
```

### 7. Lifecycle Management

```dart
@override
Future<void> close() async {
  logger.log("Closing bloc", ...);

  // Close all use case builders (for stateful use cases)
  await Future.wait<void>(_builders.map((s) => s.close()));

  // Close all aviators
  await Future.wait<void>(_aviators.values.map((a) => a.close()));
  _aviators.clear();

  // Close parent (stream controllers)
  await super.close();
}
```

---

## Code Analysis

### File Statistics

| Metric | Value |
|--------|-------|
| Total Lines | 373 |
| Lines in `_register` | 217 (58%) |
| Emit function duplication | ~120 lines |
| Public methods | 4 (`start`, `close`, `dispose`, accessors) |
| Private methods | 3 (`_initializeBloc`, `_registerBuiltInUseCases`, `_register`) |

### Complexity Hotspots

#### 1. The `_register` Method (Lines 132-349)

This method is responsible for too much:

- Creating 4 emit functions with similar logic
- Wiring use case dependencies
- Error handling
- Navigation checking
- Initial event dispatch

**Cyclomatic Complexity**: High due to nested closures and conditionals.

#### 2. Emit Function Duplication

Each emit function follows the same pattern:

```dart
void emitXxx({...}) {
  assert(!isClosed, '...');
  logger.log('Emitting xxx', context: {...});

  if (groupsToRebuild != null) {
    assert(!groupsToRebuild.contains("*") || groupsToRebuild.length == 1);
    event.groupsToRebuild = {...?event.groupsToRebuild, ...groupsToRebuild};
  }

  emit(StreamStatus.xxx(newState ?? state, state, event));
  checkNavigation(state, aviatorName, aviatorArgs);
}
```

Four copies of essentially the same code.

#### 3. Late Property Wiring

```dart
// In UseCase class
late TBloc bloc;
late void Function({...}) emitUpdate;
late void Function({...}) emitWaiting;
late void Function({...}) emitFailure;
late void Function({...}) emitCancel;
late void Function({...}) emitEvent;

// Wired at runtime in _register
usecase.bloc = this;
usecase.emitUpdate = ({...}) => emitUpdate(...);
// ...
```

No compile-time guarantee that all properties are wired.

---

## Pros and Cons

### Pros

| Category | Benefit | Impact |
|----------|---------|--------|
| **Separation of Concerns** | Business logic isolated in use cases | High |
| **State Metadata** | `StreamStatus` provides operation context | High |
| **State History** | `oldState` enables diff-based UI updates | Medium |
| **Rebuild Control** | Group-based widget rebuilding | High |
| **Navigation** | Coordinated navigation via aviators | Medium |
| **Logging** | Structured logging with context | Medium |
| **Error Handling** | Customizable with fallback protection | Medium |
| **Cleanup** | Proper async resource cleanup | Medium |
| **Flexibility** | Multiple use case builder types | High |
| **Built-in Events** | `UpdateEvent` for simple state changes | Low |

### Cons

| Category | Issue | Severity | Recommendation |
|----------|-------|----------|----------------|
| **Code Size** | `_register` is 217 lines | Medium | Extract emit logic |
| **Duplication** | 4 emit functions repeat ~30 lines each | Medium | Parameterize into single function |
| **Type Safety** | `late` properties have no compile-time guarantee | Medium | Use constructor injection |
| **Type Safety** | Runtime type casting `newState as TState?` | High | Use proper generics |
| **Type Safety** | `runtimeType` checks instead of generics | Medium | Use type parameters |
| **API Design** | Empty `[]` required for unused aviators | Low | Make parameter optional |
| **API Design** | Both `close()` and `dispose()` exist | Low | Remove `dispose()` |
| **Async Safety** | `dispose()` is `async void` | Medium | Return `Future<void>` |
| **Initialization** | No async initialization support | Medium | Add `onInit()` hook |
| **Error Recovery** | No automatic error state emission | Medium | Emit `FailureStatus` on error |
| **Validation** | No duplicate event type detection | Low | Add registration check |
| **Testability** | Closure injection harder to mock | Medium | Extract to testable classes |

---

## Refactoring Recommendations

### Priority 1: Extract Emit Logic

**Current State**: 4 functions × ~30 lines = ~120 lines of duplication

**Proposed Solution**:

```dart
// Add to JuiceBloc class
void _emitStatus({
  required StreamStatus<TState> Function(TState state, TState oldState, EventBase? event) factory,
  required String statusName,
  required EventBase event,
  required void Function(StreamStatus<TState>) emit,
  TState? newState,
  String? aviatorName,
  Map<String, dynamic>? aviatorArgs,
  Set<String>? groupsToRebuild,
}) {
  assert(!isClosed, 'Cannot emit $statusName after bloc is closed');

  logger.log('Emitting $statusName', context: {
    'type': 'state_emission',
    'status': statusName,
    'state': '$newState',
    'bloc': runtimeType.toString(),
    'groups': groupsToRebuild?.toString(),
  });

  if (groupsToRebuild != null) {
    assert(
      !groupsToRebuild.contains("*") || groupsToRebuild.length == 1,
      "Cannot mix '*' with other groups",
    );
    event.groupsToRebuild = {...?event.groupsToRebuild, ...groupsToRebuild};
  }

  emit(factory(newState ?? state, state, event));

  if (aviatorName != null && _aviators.containsKey(aviatorName)) {
    _aviators[aviatorName]?.navigateWhere.call(aviatorArgs ?? {});
  }
}

// Usage in _register
void emitUpdate({TState? newState, ...}) => _emitStatus(
  factory: StreamStatus.updating,
  statusName: 'update',
  event: event,
  emit: emit,
  newState: newState,
  aviatorName: aviatorName,
  aviatorArgs: aviatorArgs,
  groupsToRebuild: groupsToRebuild,
);
```

**Impact**: Reduces ~120 lines to ~50 lines, single point of maintenance.

---

### Priority 2: Type-Safe Use Case Context

**Current State**: `late` properties wired at runtime

**Proposed Solution**:

```dart
/// Context provided to use cases for state emission
class UseCaseContext<TBloc extends JuiceBloc<TState>, TState extends BlocState> {
  final TBloc bloc;
  final void Function({TState? newState, Set<String>? groupsToRebuild, String? aviatorName, Map<String, dynamic>? aviatorArgs}) emitUpdate;
  final void Function({TState? newState, Set<String>? groupsToRebuild, String? aviatorName, Map<String, dynamic>? aviatorArgs}) emitWaiting;
  final void Function({TState? newState, Set<String>? groupsToRebuild, String? aviatorName, Map<String, dynamic>? aviatorArgs}) emitFailure;
  final void Function({TState? newState, Set<String>? groupsToRebuild, String? aviatorName, Map<String, dynamic>? aviatorArgs}) emitCancel;
  final void Function({EventBase? event}) emitEvent;

  const UseCaseContext({
    required this.bloc,
    required this.emitUpdate,
    required this.emitWaiting,
    required this.emitFailure,
    required this.emitCancel,
    required this.emitEvent,
  });
}

/// Updated UseCase base class
abstract class UseCase<TBloc extends JuiceBloc<TState>, TState extends BlocState, TEvent extends EventBase> {
  UseCaseContext<TBloc, TState>? _context;

  @protected
  UseCaseContext<TBloc, TState> get context {
    if (_context == null) {
      throw StateError('UseCase context not initialized. This is a framework bug.');
    }
    return _context!;
  }

  TBloc get bloc => context.bloc;

  void emitUpdate({TState? newState, Set<String>? groupsToRebuild}) {
    context.emitUpdate(newState: newState, groupsToRebuild: groupsToRebuild);
  }

  // ... other emit methods

  Future<void> execute(TEvent event);
  void close() {}
}
```

**Impact**: Compile-time safety, clearer API, no `late` surprises.

---

### Priority 3: Fix Dispose Pattern

**Current State**:

```dart
@override
void dispose() async {  // async void - dangerous!
  await close();
}
```

**Proposed Solution**:

```dart
// Option A: Remove dispose entirely (prefer close)
// Just delete the dispose method

// Option B: Make dispose return Future
@override
Future<void> dispose() => close();

// Option C: Deprecate and forward
@Deprecated('Use close() instead')
@override
Future<void> dispose() => close();
```

**Impact**: Prevents silent async errors, clearer API.

---

### Priority 4: Add Async Initialization Hook

**Current State**: No way to perform async setup

**Proposed Solution**:

```dart
class JuiceBloc<TState extends BlocState> ... {
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Override for async initialization logic
  @protected
  Future<void> onInit() async {}

  /// Call after construction to perform async setup
  Future<void> initialize() async {
    if (_isInitialized) return;
    await onInit();
    _isInitialized = true;
  }
}

// Usage
class MyBloc extends JuiceBloc<MyState> {
  @override
  Future<void> onInit() async {
    final data = await repository.fetchInitialData();
    send(UpdateEvent(newState: state.copyWith(data: data)));
  }
}

// In registration
final bloc = MyBloc();
await bloc.initialize();
```

**Impact**: Enables async setup without workarounds.

---

### Priority 5: Automatic Error State Emission

**Current State**: Errors are logged but state unchanged

**Proposed Solution**:

```dart
// In _register try/catch block
catch (exception, stacktrace) {
  logger.logError('Unhandled use case exception', exception, stacktrace, context: {
    'type': 'use_case_error',
    'bloc': runtimeType.toString(),
    'event': event.runtimeType.toString()
  });

  // Emit failure state so UI can react
  emit(StreamStatus.failure(state, state, event));

  super.onError(exception, stacktrace);
}
```

**Impact**: UI automatically reflects error state.

---

### Priority 6: Optional Aviators Parameter

**Current State**:

```dart
// Must pass empty list even when not using aviators
CounterBloc() : super(CounterState(), [...useCases...], []);
```

**Proposed Solution**:

```dart
JuiceBloc(
  TState initialState,
  List<UseCaseBuilderGenerator> useCases, {
  List<AviatorBuilder> aviatorBuilders = const [],  // Optional with default
  JuiceLogger? customLogger,
  super.errorHandler = const BlocErrorHandler(),
})

// Usage
CounterBloc() : super(CounterState(), [...useCases...]);
```

**Impact**: Cleaner API for common case.

---

## Metrics

### Current State

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Lines of Code | 373 | <300 | ⚠️ Over |
| Cyclomatic Complexity | High | Medium | ⚠️ High |
| Code Duplication | ~120 lines | <20 lines | ❌ High |
| Public API Surface | 6 | <10 | ✅ Good |
| Type Safety | Medium | High | ⚠️ Improve |
| Test Coverage | Unknown | >80% | ❓ Measure |

### After Refactoring (Projected)

| Metric | Current | Projected | Improvement |
|--------|---------|-----------|-------------|
| Lines of Code | 373 | ~280 | -25% |
| Code Duplication | ~120 | ~20 | -83% |
| Type Safety Issues | 4 | 1 | -75% |
| API Clarity | Medium | High | Significant |

---

## Appendix: Key Type Definitions

```dart
// State wrapper with operation metadata
abstract class StreamStatus<TState extends BlocState> {
  final TState state;
  final TState oldState;
  final EventBase? event;

  factory StreamStatus.updating(...) = UpdatingStatus;
  factory StreamStatus.waiting(...) = WaitingStatus;
  factory StreamStatus.failure(...) = FailureStatus;
  factory StreamStatus.canceling(...) = CancelingStatus;
}

// Base event class
abstract class EventBase {
  Set<String>? groupsToRebuild;
}

// Use case builder types
typedef UseCaseBuilderGenerator = UseCaseBuilderBase Function();
typedef UseCaseGenerator = UseCase Function();
typedef UseCaseEventBuilder = EventBase Function();

// Aviator type
typedef AviatorBuilder = AviatorBase Function();
```

---

## Related Documents

- [PROPOSED_IMPROVEMENTS.md](./PROPOSED_IMPROVEMENTS.md) - Framework-wide improvement proposals
- [concepts/use-cases.md](./concepts/use-cases.md) - Use case pattern documentation
- [concepts/state-management.md](./concepts/state-management.md) - State management concepts
