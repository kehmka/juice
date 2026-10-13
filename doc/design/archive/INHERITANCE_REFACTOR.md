# JuiceBloc Inheritance Refactoring

Full refactoring plan to replace the three-level inheritance (`BlocBase → Bloc → JuiceBloc`) with a composition-based architecture.

---

## Current State

```
BlocBase<State>                    (104 lines)
    │
    ▼
Bloc<Event, State>                 (158 lines)
    │
    ▼
JuiceBloc<TState>                  (373 lines)

Total: 635 lines, 3 inheritance levels
```

### Problems

| Issue | Impact |
|-------|--------|
| Deep inheritance (3 levels) | Hard to understand, debug, and test |
| Bloc is a "middle manager" | Adds complexity without clear value |
| Dual systems | `Bloc._handlers` duplicates `JuiceBloc._builders` |
| Type complexity | `Bloc<EventBase, StreamStatus<TState>>` is confusing |
| Tight coupling | Can't use components independently |
| Testing difficulty | Must mock/understand all 3 layers |

---

## Target State: Composition Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           JuiceBloc<TState>                             │
│                                                                         │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐   │
│  │   StateManager   │  │  EventDispatcher │  │   UseCaseExecutor    │   │
│  │   <StreamStatus> │  │   <EventBase>    │  │                      │   │
│  │                  │  │                  │  │                      │   │
│  │  - emit(state)   │  │  - dispatch()    │  │  - execute(useCase)  │   │
│  │  - stream        │  │  - register()    │  │  - createContext()   │   │
│  │  - current       │  │                  │  │                      │   │
│  └──────────────────┘  └──────────────────┘  └──────────────────────┘   │
│                                                                         │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐   │
│  │ UseCaseRegistry  │  │  AviatorManager  │  │    ErrorHandler      │   │
│  │                  │  │                  │  │                      │   │
│  │  - builders      │  │  - aviators      │  │  - handleError()     │   │
│  │  - register()    │  │  - navigate()    │  │  - onError callback  │   │
│  └──────────────────┘  └──────────────────┘  └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘

Total: ~500 lines across 7 focused classes
```

---

## Component Specifications

### 1. StateManager

Manages state storage and stream emission.

```dart
// lib/src/bloc/src/core/state_manager.dart

import 'dart:async';

/// Manages state storage and stream emission for a bloc.
///
/// This is a pure state container with no knowledge of events or use cases.
class StateManager<State> {
  /// Creates a StateManager with an initial state.
  StateManager(State initialState) : _state = initialState;

  final _controller = StreamController<State>.broadcast();
  State _state;
  bool _isClosed = false;

  /// The current state.
  State get current => _state;

  /// Stream of state changes.
  Stream<State> get stream => _controller.stream;

  /// Whether the manager has been closed.
  bool get isClosed => _isClosed;

  /// Emits a new state to all listeners.
  ///
  /// Throws [StateError] if called after [close].
  void emit(State state) {
    if (_isClosed) {
      throw StateError('Cannot emit state after StateManager is closed');
    }
    _state = state;
    _controller.add(state);
  }

  /// Closes the state manager and its stream.
  ///
  /// After calling close, no more states can be emitted.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _controller.close();
  }
}
```

**Responsibilities:**
- Store current state
- Broadcast state changes via stream
- Track closed status

**Does NOT handle:**
- Events
- Use cases
- Logging

---

### 2. EventDispatcher

Routes events to registered handlers.

```dart
// lib/src/bloc/src/core/event_dispatcher.dart

import 'dart:async';

/// Signature for event handlers.
typedef EventHandler<E> = Future<void> Function(E event);

/// Routes events to their registered handlers.
///
/// Each event type can have exactly one handler registered.
class EventDispatcher<Event> {
  final _handlers = <Type, EventHandler<Event>>{};
  final void Function(Event event)? _onUnhandledEvent;

  /// Creates an EventDispatcher.
  ///
  /// [onUnhandledEvent] is called when an event has no registered handler.
  EventDispatcher({void Function(Event event)? onUnhandledEvent})
      : _onUnhandledEvent = onUnhandledEvent;

  /// Registers a handler for a specific event type.
  ///
  /// [E] is the event type to handle.
  /// [handler] is the function to call when events of type [E] are dispatched.
  /// [eventType] optionally overrides the runtime type (useful for generic events).
  void register<E extends Event>(
    EventHandler<E> handler, {
    Type? eventType,
  }) {
    final type = eventType ?? E;
    if (_handlers.containsKey(type)) {
      throw StateError('Handler already registered for $type');
    }
    _handlers[type] = (event) => handler(event as E);
  }

  /// Checks if a handler is registered for the given event type.
  bool hasHandler(Type eventType) => _handlers.containsKey(eventType);

  /// Dispatches an event to its registered handler.
  ///
  /// Returns a Future that completes when the handler finishes.
  /// If no handler is registered, calls [onUnhandledEvent] or throws.
  Future<void> dispatch(Event event) async {
    final handler = _handlers[event.runtimeType];
    if (handler == null) {
      if (_onUnhandledEvent != null) {
        _onUnhandledEvent!(event);
        return;
      }
      throw StateError('No handler registered for ${event.runtimeType}');
    }
    await handler(event);
  }

  /// Removes all registered handlers.
  void clear() {
    _handlers.clear();
  }
}
```

**Responsibilities:**
- Map event types to handlers
- Dispatch events to correct handler
- Report unhandled events

**Does NOT handle:**
- State management
- Use case lifecycle
- Logging

---

### 3. UseCaseRegistry

Stores and manages use case builders.

```dart
// lib/src/bloc/src/core/use_case_registry.dart

import 'dart:async';
import '../bloc.dart';

/// Stores and manages use case builders.
///
/// Handles registration, lookup, and cleanup of use case builders.
class UseCaseRegistry {
  final _builders = <Type, UseCaseBuilderBase>{};

  /// Registers a use case builder for its event type.
  ///
  /// Throws [StateError] if a builder is already registered for the event type.
  void register(UseCaseBuilderBase builder) {
    final eventType = builder.eventType;
    if (_builders.containsKey(eventType)) {
      throw StateError('UseCase already registered for $eventType');
    }
    _builders[eventType] = builder;
  }

  /// Gets the builder for a specific event type.
  ///
  /// Returns null if no builder is registered.
  UseCaseBuilderBase? getBuilder(Type eventType) {
    return _builders[eventType];
  }

  /// Checks if a builder exists for the event type.
  bool hasBuilder(Type eventType) => _builders.containsKey(eventType);

  /// All registered builders.
  Iterable<UseCaseBuilderBase> get builders => _builders.values;

  /// Closes all registered builders.
  ///
  /// Should be called when the owning bloc is closed.
  Future<void> closeAll() async {
    await Future.wait(_builders.values.map((b) => b.close()));
    _builders.clear();
  }
}
```

---

### 4. UseCaseExecutor

Executes use cases with proper context injection.

```dart
// lib/src/bloc/src/core/use_case_executor.dart

import 'dart:async';
import '../bloc.dart';

/// Context provided to use cases for state emission.
class UseCaseContext<TBloc, TState extends BlocState> {
  final TBloc bloc;
  final TState Function() getState;
  final TState Function() getOldState;
  final void Function(TState? newState, Set<String>? groups) emitUpdate;
  final void Function(TState? newState, Set<String>? groups) emitWaiting;
  final void Function(TState? newState, Set<String>? groups) emitFailure;
  final void Function(TState? newState, Set<String>? groups) emitCancel;
  final void Function(String? aviator, Map<String, dynamic>? args) navigate;

  const UseCaseContext({
    required this.bloc,
    required this.getState,
    required this.getOldState,
    required this.emitUpdate,
    required this.emitWaiting,
    required this.emitFailure,
    required this.emitCancel,
    required this.navigate,
  });
}

/// Executes use cases with injected context.
class UseCaseExecutor<TBloc, TState extends BlocState> {
  final UseCaseContext<TBloc, TState> Function(EventBase event) _contextFactory;
  final void Function(Object error, StackTrace stack, EventBase event) _onError;
  final JuiceLogger _logger;

  UseCaseExecutor({
    required UseCaseContext<TBloc, TState> Function(EventBase event) contextFactory,
    required void Function(Object error, StackTrace stack, EventBase event) onError,
    required JuiceLogger logger,
  })  : _contextFactory = contextFactory,
        _onError = onError,
        _logger = logger;

  /// Executes a use case for the given event.
  Future<void> execute(UseCaseBuilderBase builder, EventBase event) async {
    final useCase = builder.generator();
    final context = _contextFactory(event);

    _logger.log('Executing use case', context: {
      'type': 'use_case_execution',
      'useCase': useCase.runtimeType.toString(),
      'event': event.runtimeType.toString(),
    });

    // Wire the use case
    _wireUseCase(useCase, context);

    try {
      await useCase.execute(event);
    } catch (error, stackTrace) {
      _logger.logError(
        'Use case execution failed',
        error,
        stackTrace,
        context: {
          'useCase': useCase.runtimeType.toString(),
          'event': event.runtimeType.toString(),
        },
      );
      _onError(error, stackTrace, event);
      rethrow;
    }
  }

  void _wireUseCase(UseCase useCase, UseCaseContext<TBloc, TState> context) {
    useCase.bloc = context.bloc;
    useCase.emitUpdate = ({newState, groupsToRebuild, aviatorName, aviatorArgs}) {
      context.emitUpdate(newState as TState?, groupsToRebuild);
      context.navigate(aviatorName, aviatorArgs);
    };
    useCase.emitWaiting = ({newState, groupsToRebuild, aviatorName, aviatorArgs}) {
      context.emitWaiting(newState as TState?, groupsToRebuild);
      context.navigate(aviatorName, aviatorArgs);
    };
    useCase.emitFailure = ({newState, groupsToRebuild, aviatorName, aviatorArgs}) {
      context.emitFailure(newState as TState?, groupsToRebuild);
      context.navigate(aviatorName, aviatorArgs);
    };
    useCase.emitCancel = ({newState, groupsToRebuild, aviatorName, aviatorArgs}) {
      context.emitCancel(newState as TState?, groupsToRebuild);
      context.navigate(aviatorName, aviatorArgs);
    };
  }
}
```

---

### 5. StatusEmitter

Handles StreamStatus emission with logging.

```dart
// lib/src/bloc/src/core/status_emitter.dart

import '../bloc.dart';

/// Handles emission of StreamStatus with proper logging and group management.
class StatusEmitter<TState extends BlocState> {
  final StateManager<StreamStatus<TState>> _stateManager;
  final JuiceLogger _logger;
  final String _blocName;

  StatusEmitter({
    required StateManager<StreamStatus<TState>> stateManager,
    required JuiceLogger logger,
    required String blocName,
  })  : _stateManager = stateManager,
        _logger = logger,
        _blocName = blocName;

  TState get state => _stateManager.current.state;
  TState get oldState => _stateManager.current.oldState;

  /// Emits an updating status.
  void emitUpdate(EventBase event, TState? newState, Set<String>? groups) {
    _emit(StreamStatus.updating, 'update', event, newState, groups);
  }

  /// Emits a waiting status.
  void emitWaiting(EventBase event, TState? newState, Set<String>? groups) {
    _emit(StreamStatus.waiting, 'waiting', event, newState, groups);
  }

  /// Emits a failure status.
  void emitFailure(EventBase event, TState? newState, Set<String>? groups) {
    _emit(StreamStatus.failure, 'failure', event, newState, groups);
  }

  /// Emits a canceling status.
  void emitCancel(EventBase event, TState? newState, Set<String>? groups) {
    _emit(StreamStatus.canceling, 'cancel', event, newState, groups);
  }

  void _emit(
    StreamStatus<TState> Function(TState, TState, EventBase?) factory,
    String statusName,
    EventBase event,
    TState? newState,
    Set<String>? groupsToRebuild,
  ) {
    if (_stateManager.isClosed) {
      throw StateError('Cannot emit $statusName after bloc is closed');
    }

    _logger.log('Emitting $statusName', context: {
      'type': 'state_emission',
      'status': statusName,
      'state': '${newState ?? state}',
      'bloc': _blocName,
      'groups': groupsToRebuild?.toString(),
    });

    if (groupsToRebuild != null) {
      assert(
        !groupsToRebuild.contains('*') || groupsToRebuild.length == 1,
        "Cannot mix '*' with other groups",
      );
      event.groupsToRebuild = {...?event.groupsToRebuild, ...groupsToRebuild};
    }

    _stateManager.emit(factory(newState ?? state, state, event));
  }
}
```

---

### 6. AviatorManager

Manages navigation aviators.

```dart
// lib/src/bloc/src/core/aviator_manager.dart

import 'dart:async';
import '../bloc.dart';

/// Manages navigation aviators for a bloc.
class AviatorManager {
  final _aviators = <String, AviatorBase>{};

  /// Registers an aviator.
  void register(AviatorBase aviator) {
    _aviators[aviator.name] = aviator;
  }

  /// Navigates using the named aviator.
  void navigate(String? aviatorName, Map<String, dynamic>? args) {
    if (aviatorName == null) return;
    final aviator = _aviators[aviatorName];
    if (aviator != null) {
      aviator.navigateWhere.call(args ?? {});
    }
  }

  /// Checks if an aviator exists.
  bool hasAviator(String name) => _aviators.containsKey(name);

  /// Closes all aviators.
  Future<void> closeAll() async {
    await Future.wait(_aviators.values.map((a) => a.close()));
    _aviators.clear();
  }
}
```

---

### 7. Refactored JuiceBloc

The main class that composes all components.

```dart
// lib/src/bloc/src/juice_bloc.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'core/state_manager.dart';
import 'core/event_dispatcher.dart';
import 'core/use_case_registry.dart';
import 'core/use_case_executor.dart';
import 'core/status_emitter.dart';
import 'core/aviator_manager.dart';
import 'bloc.dart';

/// A bloc that manages state through use cases.
///
/// JuiceBloc provides structured state management by routing events to
/// dedicated use cases, which encapsulate business logic and emit state
/// changes.
///
/// Example:
/// ```dart
/// class CounterBloc extends JuiceBloc<CounterState> {
///   CounterBloc() : super(
///     CounterState(count: 0),
///     [
///       () => UseCaseBuilder(
///         typeOfEvent: IncrementEvent,
///         useCaseGenerator: () => IncrementUseCase(),
///       ),
///     ],
///   );
/// }
/// ```
class JuiceBloc<TState extends BlocState> {
  /// Creates a JuiceBloc with initial state and use cases.
  JuiceBloc(
    TState initialState,
    List<UseCaseBuilderGenerator> useCases, {
    List<AviatorBuilder> aviatorBuilders = const [],
    JuiceLogger? customLogger,
    BlocErrorHandler errorHandler = const BlocErrorHandler(),
  })  : _logger = customLogger ?? JuiceLoggerConfig.logger,
        _errorHandler = errorHandler,
        _stateManager = StateManager(
          StreamStatus.updating(initialState, initialState, null),
        ) {
    _statusEmitter = StatusEmitter(
      stateManager: _stateManager,
      logger: _logger,
      blocName: runtimeType.toString(),
    );

    _useCaseExecutor = UseCaseExecutor(
      contextFactory: _createContext,
      onError: _handleUseCaseError,
      logger: _logger,
    );

    _dispatcher = EventDispatcher(
      onUnhandledEvent: _handleUnhandledEvent,
    );

    _initialize(useCases, aviatorBuilders);
  }

  // Components
  final StateManager<StreamStatus<TState>> _stateManager;
  late final StatusEmitter<TState> _statusEmitter;
  late final EventDispatcher<EventBase> _dispatcher;
  late final UseCaseExecutor<JuiceBloc<TState>, TState> _useCaseExecutor;
  final UseCaseRegistry _useCaseRegistry = UseCaseRegistry();
  final AviatorManager _aviatorManager = AviatorManager();

  // Configuration
  final JuiceLogger _logger;
  final BlocErrorHandler _errorHandler;

  // ============================================================
  // Public API
  // ============================================================

  /// The current state.
  TState get state => _stateManager.current.state;

  /// The previous state.
  TState get oldState => _stateManager.current.oldState;

  /// The current status with metadata.
  StreamStatus<TState> get currentStatus => _stateManager.current;

  /// Stream of status changes.
  Stream<StreamStatus<TState>> get stream => _stateManager.stream;

  /// Whether the bloc is closed.
  bool get isClosed => _stateManager.isClosed;

  /// Sends an event to be processed by its registered use case.
  Future<void> send(EventBase event) => _dispatcher.dispatch(event);

  /// Sends a cancellable event and returns it for cancellation control.
  T sendCancellable<T extends CancellableEvent>(T event) {
    send(event);
    return event;
  }

  /// Triggers an update with the current state.
  void start() => send(UpdateEvent(newState: state));

  /// Closes the bloc and releases all resources.
  Future<void> close() async {
    if (isClosed) return;

    _logger.log('Closing bloc', context: {
      'type': 'bloc_lifecycle',
      'action': 'close',
      'bloc': runtimeType.toString(),
    });

    await _useCaseRegistry.closeAll();
    await _aviatorManager.closeAll();
    _dispatcher.clear();
    await _stateManager.close();
  }

  // ============================================================
  // Initialization
  // ============================================================

  void _initialize(
    List<UseCaseBuilderGenerator> useCases,
    List<AviatorBuilder> aviatorBuilders,
  ) {
    _registerBuiltInUseCases();
    _registerUseCases(useCases);
    _registerAviators(aviatorBuilders);
  }

  void _registerBuiltInUseCases() {
    _registerUseCase(UseCaseBuilder(
      typeOfEvent: UpdateEvent,
      useCaseGenerator: () => UpdateUseCase(),
    ));
    _registerUseCase(UseCaseBuilder(
      typeOfEvent: UpdateEvent<TState>,
      useCaseGenerator: () => UpdateUseCase(),
    ));
  }

  void _registerUseCases(List<UseCaseBuilderGenerator> useCases) {
    for (final generator in useCases) {
      final builder = generator();
      _registerUseCase(builder);

      // Fire initial event if configured
      if (builder.initialEventBuilder != null) {
        final event = builder.initialEventBuilder!();
        if (event.runtimeType == builder.eventType) {
          send(event);
        }
      }
    }
  }

  void _registerUseCase(UseCaseBuilderBase builder) {
    _useCaseRegistry.register(builder);

    _dispatcher.register<EventBase>(
      (event) => _useCaseExecutor.execute(builder, event),
      eventType: builder.eventType,
    );
  }

  void _registerAviators(List<AviatorBuilder> aviatorBuilders) {
    for (final generator in aviatorBuilders) {
      _aviatorManager.register(generator());
    }
  }

  // ============================================================
  // Context Factory
  // ============================================================

  UseCaseContext<JuiceBloc<TState>, TState> _createContext(EventBase event) {
    return UseCaseContext(
      bloc: this,
      getState: () => state,
      getOldState: () => oldState,
      emitUpdate: (newState, groups) =>
          _statusEmitter.emitUpdate(event, newState, groups),
      emitWaiting: (newState, groups) =>
          _statusEmitter.emitWaiting(event, newState, groups),
      emitFailure: (newState, groups) =>
          _statusEmitter.emitFailure(event, newState, groups),
      emitCancel: (newState, groups) =>
          _statusEmitter.emitCancel(event, newState, groups),
      navigate: _aviatorManager.navigate,
    );
  }

  // ============================================================
  // Error Handling
  // ============================================================

  void _handleUnhandledEvent(EventBase event) {
    final message = 'No use case registered for ${event.runtimeType}';
    _logger.logError(message, StateError(message), StackTrace.current, context: {
      'type': 'unhandled_event',
      'bloc': runtimeType.toString(),
      'event': event.runtimeType.toString(),
    });
    _errorHandler.handleError(message);
  }

  void _handleUseCaseError(Object error, StackTrace stack, EventBase event) {
    _logger.logError('Use case error', error, stack, context: {
      'type': 'use_case_error',
      'bloc': runtimeType.toString(),
      'event': event.runtimeType.toString(),
      'state': state.toString(),
    });

    _errorHandler.handleError(
      'Use case error',
      error: error,
      stackTrace: stack,
    );
  }

  /// Called when an error occurs. Override to customize error handling.
  @protected
  void onError(Object error, StackTrace stackTrace) {
    _logger.logError('Bloc error', error, stackTrace, context: {
      'type': 'bloc_error',
      'bloc': runtimeType.toString(),
      'state': state.toString(),
    });
  }
}
```

---

## File Structure

```
lib/src/bloc/
├── src/
│   ├── core/                          # NEW: Core components
│   │   ├── state_manager.dart         # State storage and streaming
│   │   ├── event_dispatcher.dart      # Event routing
│   │   ├── use_case_registry.dart     # Builder storage
│   │   ├── use_case_executor.dart     # Use case execution
│   │   ├── status_emitter.dart        # StreamStatus emission
│   │   └── aviator_manager.dart       # Navigation management
│   │
│   ├── juice_bloc.dart                # REFACTORED: Composes components
│   ├── bloc_state.dart                # Unchanged
│   ├── bloc_event.dart                # Unchanged
│   ├── stream_status.dart             # Unchanged
│   ├── usecase.dart                   # Minor updates for context
│   ├── bloc_use_case.dart             # Unchanged
│   │
│   ├── use_case_builders/             # Unchanged
│   └── aviators/                      # Unchanged
│
├── bloc.dart                          # Updated exports
│
└── DELETED:
    ├── bloc.dart                      # Remove Bloc class
    └── bloc_base.dart                 # Remove BlocBase class
```

---

## Migration Guide

### For Framework Users

**No breaking changes to public API.** The following all work identically:

```dart
// Creating blocs - unchanged
class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc() : super(
    CounterState(count: 0),
    [
      () => UseCaseBuilder(
        typeOfEvent: IncrementEvent,
        useCaseGenerator: () => IncrementUseCase(),
      ),
    ],
  );
}

// Using blocs - unchanged
bloc.send(IncrementEvent());
bloc.state.count;
bloc.stream.listen((status) { ... });
await bloc.close();
```

### For Use Case Authors

**Minor update**: Use case context is now injected differently internally, but the public API (`emitUpdate`, `emitWaiting`, etc.) is unchanged.

```dart
// Still works exactly the same
class IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(count: bloc.state.count + 1),
      groupsToRebuild: {"counter"},
    );
  }
}
```

---

## Benefits

| Benefit | Description |
|---------|-------------|
| **Testability** | Each component can be unit tested in isolation |
| **Single Responsibility** | Each class has one clear purpose |
| **No Deep Inheritance** | Flat structure, easier to understand |
| **Flexibility** | Can swap implementations (e.g., different StateManager) |
| **Smaller Files** | ~80-100 lines each vs 373 lines monolith |
| **Maintainability** | Changes to one concern don't affect others |
| **Reusability** | Components can be used in other contexts |

## Metrics Comparison

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Total Lines | 635 | ~500 | -21% |
| Max File Size | 373 | ~150 | -60% |
| Inheritance Depth | 3 | 1 | -67% |
| Classes | 3 | 7 | +133% (but smaller) |
| Cyclomatic Complexity | High | Low | Significant |
| Test Surface | Hard | Easy | Significant |

---

## Implementation Order

1. **Create core components** (non-breaking)
   - StateManager
   - EventDispatcher
   - UseCaseRegistry
   - StatusEmitter
   - AviatorManager
   - UseCaseExecutor

2. **Create new JuiceBloc** (as JuiceBlocV2 initially)
   - Compose components
   - Match existing public API
   - Add comprehensive tests

3. **Migrate and validate**
   - Run all existing tests against new implementation
   - Ensure example app works
   - Performance benchmarks

4. **Switch over**
   - Replace old JuiceBloc with new
   - Delete Bloc and BlocBase
   - Update exports

5. **Cleanup**
   - Remove deprecated code
   - Update documentation
   - Version bump
