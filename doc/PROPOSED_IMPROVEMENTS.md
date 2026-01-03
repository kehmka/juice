# Juice Framework - Proposed Improvements

This document outlines improvements to address complexity, developer experience, and ecosystem gaps in the Juice framework.

---

## Table of Contents

1. [Layered API for Simpler Use Cases](#1-layered-api-for-simpler-use-cases)
2. [Inline Use Cases to Reduce File Count](#2-inline-use-cases-to-reduce-file-count)
3. [Event Tracing and Debugging](#3-event-tracing-and-debugging)
4. [Scoped Bloc Registration](#4-scoped-bloc-registration)
5. [Type-Safe Rebuild Groups](#5-type-safe-rebuild-groups)
6. [DevTools Extension](#6-devtools-extension)
7. [Flexible Widget Integration](#7-flexible-widget-integration)
8. [Code Generation](#8-code-generation)

---

## 1. Layered API for Simpler Use Cases

### Problem
Every use case requires a dedicated class, even for trivial operations like incrementing a counter.

### Solution
Add a simple inline handler API alongside the existing pattern.

### Implementation

```dart
// lib/src/bloc/src/use_case_builders/src/inline_use_case_builder.dart

/// A use case builder that accepts an inline function instead of a class.
/// Ideal for simple, stateless operations.
class InlineUseCaseBuilder<TBloc extends JuiceBloc, TEvent extends EventBase>
    extends UseCaseBuilderBase {
  InlineUseCaseBuilder({
    required this.typeOfEvent,
    required this.handler,
    this.initialEventBuilder,
  });

  final Type typeOfEvent;
  final Future<void> Function(TBloc bloc, TEvent event, Emitters emitters) handler;
  final UseCaseEventBuilder? initialEventBuilder;

  @override
  Type get eventType => typeOfEvent;

  @override
  UseCaseEventBuilder? get initialEventBuilder => _initialEventBuilder;
  final UseCaseEventBuilder? _initialEventBuilder;

  @override
  UseCaseGenerator get generator => () => _InlineUseCase<TBloc, TEvent>(handler);

  @override
  Future<void> close() async {}
}

/// Helper class containing emit functions
class Emitters {
  final void Function({BlocState? newState, Set<String>? groupsToRebuild}) emitUpdate;
  final void Function({BlocState? newState, Set<String>? groupsToRebuild}) emitWaiting;
  final void Function({BlocState? newState, Set<String>? groupsToRebuild}) emitFailure;

  Emitters({
    required this.emitUpdate,
    required this.emitWaiting,
    required this.emitFailure,
  });
}

class _InlineUseCase<TBloc extends JuiceBloc, TEvent extends EventBase>
    extends UseCase<TBloc, TEvent> {
  final Future<void> Function(TBloc bloc, TEvent event, Emitters emitters) handler;

  _InlineUseCase(this.handler);

  @override
  Future<void> execute(TEvent event) async {
    await handler(
      bloc as TBloc,
      event,
      Emitters(
        emitUpdate: emitUpdate,
        emitWaiting: emitWaiting,
        emitFailure: emitFailure,
      ),
    );
  }
}
```

### Usage

```dart
// Before: Requires separate file and class
class IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(count: bloc.state.count + 1),
      groupsToRebuild: {"counter"},
    );
  }
}

// After: Inline for simple cases
class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc() : super(
    CounterState(count: 0),
    [
      () => InlineUseCaseBuilder<CounterBloc, IncrementEvent>(
        typeOfEvent: IncrementEvent,
        handler: (bloc, event, emit) async {
          emit.emitUpdate(
            newState: bloc.state.copyWith(count: bloc.state.count + 1),
            groupsToRebuild: {"counter"},
          );
        },
      ),
    ],
    [],
  );
}
```

### Files to Modify
- `lib/src/bloc/src/use_case_builders/use_case_builder.dart` - Add export
- `lib/src/bloc/bloc.dart` - Add export

---

## 2. Inline Use Cases to Reduce File Count

### Problem
A simple feature like counter requires 6+ files, which is excessive for trivial features.

### Solution
Support Dart `part` files and provide a single-file template for simple features.

### Template: Single-File Feature

```dart
// lib/blocs/counter/counter.dart

part 'counter_state.dart';
part 'counter_events.dart';

class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc() : super(
    CounterState(count: 0),
    [
      () => InlineUseCaseBuilder<CounterBloc, IncrementEvent>(
        typeOfEvent: IncrementEvent,
        handler: (bloc, event, emit) async {
          emit.emitUpdate(
            newState: bloc.state.copyWith(count: bloc.state.count + 1),
            groupsToRebuild: CounterGroups.display,
          );
        },
      ),
      () => InlineUseCaseBuilder<CounterBloc, DecrementEvent>(
        typeOfEvent: DecrementEvent,
        handler: (bloc, event, emit) async {
          emit.emitUpdate(
            newState: bloc.state.copyWith(count: bloc.state.count - 1),
            groupsToRebuild: CounterGroups.display,
          );
        },
      ),
    ],
    [],
  );
}

// Type-safe groups
abstract class CounterGroups {
  static const display = {"counter_display"};
  static const all = {"counter_display"};
}
```

```dart
// counter_state.dart
part of 'counter.dart';

class CounterState extends BlocState {
  final int count;
  CounterState({required this.count});
  CounterState copyWith({int? count}) => CounterState(count: count ?? this.count);
}
```

```dart
// counter_events.dart
part of 'counter.dart';

class IncrementEvent extends EventBase {}
class DecrementEvent extends EventBase {}
```

### Result
- **Before**: 6+ files (bloc, state, events, 3 use cases)
- **After**: 3 files (or 1 file if state/events are small)

---

## 3. Event Tracing and Debugging

### Problem
Indirect event flow makes debugging difficult. Hard to trace event → use case → state emission → widget rebuild.

### Solution
Add built-in tracing with unique trace IDs.

### Implementation

```dart
// lib/src/bloc/src/juice_tracer.dart

/// Trace entry for debugging event flow
class TraceEntry {
  final String traceId;
  final DateTime timestamp;
  final String phase; // EVENT_RECEIVED, USE_CASE_START, STATE_EMITTED, WIDGET_REBUILD
  final String bloc;
  final String? event;
  final String? useCase;
  final String? status;
  final Set<String>? groups;
  final String? widget;

  TraceEntry({
    required this.traceId,
    required this.timestamp,
    required this.phase,
    required this.bloc,
    this.event,
    this.useCase,
    this.status,
    this.groups,
    this.widget,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[$traceId] $phase: ');
    if (event != null) buffer.write('$event → ');
    buffer.write(bloc);
    if (useCase != null) buffer.write(' ($useCase)');
    if (status != null) buffer.write(' → $status');
    if (groups != null) buffer.write(' [${groups!.join(", ")}]');
    if (widget != null) buffer.write(' → $widget');
    return buffer.toString();
  }
}

/// Global tracer for debugging
class JuiceTracer {
  static final JuiceTracer _instance = JuiceTracer._();
  factory JuiceTracer() => _instance;
  JuiceTracer._();

  bool enabled = false;
  final List<TraceEntry> _traces = [];
  final _controller = StreamController<TraceEntry>.broadcast();

  Stream<TraceEntry> get stream => _controller.stream;
  List<TraceEntry> get traces => List.unmodifiable(_traces);

  String generateTraceId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  void trace(TraceEntry entry) {
    if (!enabled) return;
    _traces.add(entry);
    _controller.add(entry);

    // Also log to console in debug mode
    assert(() {
      print(entry);
      return true;
    }());
  }

  void clear() => _traces.clear();
}
```

### Integration in JuiceBloc

```dart
// In juice_bloc.dart _register method

register<TEvent>((event, emit) async {
  final traceId = JuiceTracer().generateTraceId();

  JuiceTracer().trace(TraceEntry(
    traceId: traceId,
    timestamp: DateTime.now(),
    phase: 'EVENT_RECEIVED',
    bloc: runtimeType.toString(),
    event: event.runtimeType.toString(),
  ));

  // Store traceId on event for downstream tracing
  event.traceId = traceId;

  try {
    var usecase = handler.call();

    JuiceTracer().trace(TraceEntry(
      traceId: traceId,
      timestamp: DateTime.now(),
      phase: 'USE_CASE_START',
      bloc: runtimeType.toString(),
      useCase: usecase.runtimeType.toString(),
    ));

    // ... execute use case ...

  } catch (e, st) {
    JuiceTracer().trace(TraceEntry(
      traceId: traceId,
      timestamp: DateTime.now(),
      phase: 'USE_CASE_ERROR',
      bloc: runtimeType.toString(),
      event: e.toString(),
    ));
    rethrow;
  }
});
```

### Usage

```dart
// Enable tracing in debug mode
void main() {
  assert(() {
    JuiceTracer().enabled = true;
    JuiceTracer().stream.listen((entry) {
      // Custom handling, e.g., send to DevTools
    });
    return true;
  }());

  runApp(MyApp());
}
```

### Output Example

```
[k8f3x] EVENT_RECEIVED: IncrementEvent → CounterBloc
[k8f3x] USE_CASE_START: CounterBloc (IncrementUseCase)
[k8f3x] STATE_EMITTED: CounterBloc → UpdatingStatus [counter_display]
[k8f3x] WIDGET_REBUILD: CounterWidget (matched: counter_display)
```

---

## 4. Scoped Bloc Registration

### Problem
`GlobalBlocResolver` creates implicit dependencies, making testing harder and registration order fragile.

### Solution
Add `JuiceScope` widget for scoped, explicit bloc registration.

### Implementation

```dart
// lib/src/ui/src/juice_scope.dart

/// Provides scoped bloc registration with InheritedWidget.
/// Child scopes inherit parent blocs and can add their own.
class JuiceScope extends StatefulWidget {
  final List<JuiceBloc Function()> blocs;
  final Widget child;
  final bool disposeOnUnmount;

  const JuiceScope({
    super.key,
    required this.blocs,
    required this.child,
    this.disposeOnUnmount = true,
  });

  /// Get the nearest JuiceScope's resolver
  static BlocDependencyResolver of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_JuiceScopeInherited>();
    if (scope == null) {
      throw StateError(
        'No JuiceScope found in widget tree. '
        'Wrap your app or feature with JuiceScope.',
      );
    }
    return scope.resolver;
  }

  /// Try to get resolver, returns null if no scope found
  static BlocDependencyResolver? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_JuiceScopeInherited>()?.resolver;
  }

  @override
  State<JuiceScope> createState() => _JuiceScopeState();
}

class _JuiceScopeState extends State<JuiceScope> {
  late final _ScopedResolver _resolver;
  final List<JuiceBloc> _createdBlocs = [];

  @override
  void initState() {
    super.initState();
    _resolver = _ScopedResolver();

    for (final factory in widget.blocs) {
      final bloc = factory();
      _createdBlocs.add(bloc);
      _resolver.register(bloc);
    }
  }

  @override
  void dispose() {
    if (widget.disposeOnUnmount) {
      for (final bloc in _createdBlocs) {
        bloc.close();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Try to get parent resolver and chain it
    final parentResolver = JuiceScope.maybeOf(context);
    _resolver.parent = parentResolver;

    return _JuiceScopeInherited(
      resolver: _resolver,
      child: widget.child,
    );
  }
}

class _JuiceScopeInherited extends InheritedWidget {
  final BlocDependencyResolver resolver;

  const _JuiceScopeInherited({
    required this.resolver,
    required super.child,
  });

  @override
  bool updateShouldNotify(_JuiceScopeInherited oldWidget) {
    return resolver != oldWidget.resolver;
  }
}

class _ScopedResolver implements BlocDependencyResolver {
  final Map<Type, JuiceBloc> _blocs = {};
  BlocDependencyResolver? parent;

  void register<T extends JuiceBloc>(T bloc) {
    _blocs[T] = bloc;
  }

  @override
  T resolve<T extends JuiceBloc>() {
    // Check local scope first
    if (_blocs.containsKey(T)) {
      return _blocs[T] as T;
    }
    // Fall back to parent scope
    if (parent != null) {
      return parent!.resolve<T>();
    }
    throw StateError('No bloc of type $T found in scope hierarchy');
  }
}
```

### Usage

```dart
// App-level blocs
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return JuiceScope(
      blocs: [
        () => AuthBloc(),
        () => SettingsBloc(),
      ],
      child: MaterialApp(
        home: HomePage(),
      ),
    );
  }
}

// Feature-level blocs (inherit app blocs)
class CounterFeature extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return JuiceScope(
      blocs: [
        () => CounterBloc(),
      ],
      child: CounterPage(),
    );
  }
}
```

### Migration Path
- Keep `GlobalBlocResolver` for backward compatibility
- Widgets check for `JuiceScope.maybeOf(context)` first, fall back to global

---

## 5. Type-Safe Rebuild Groups

### Problem
Rebuild groups are stringly-typed, leading to silent bugs from typos.

### Solution
Define groups as typed constants with optional linting.

### Implementation

```dart
// lib/src/bloc/src/rebuild_group.dart

/// Base class for defining type-safe rebuild groups.
/// Extend this for each bloc to define its groups.
abstract class RebuildGroups {
  /// All groups defined by this class
  Set<String> get all;
}

/// Mixin to add group validation to blocs
mixin RebuildGroupValidation<T extends RebuildGroups> on JuiceBloc {
  T get groups;

  @override
  void validateGroups(Set<String>? groupsToRebuild) {
    if (groupsToRebuild == null) return;
    if (groupsToRebuild.contains('*')) return;

    final invalidGroups = groupsToRebuild.difference(groups.all);
    if (invalidGroups.isNotEmpty) {
      assert(
        false,
        'Invalid rebuild groups: $invalidGroups. '
        'Valid groups are: ${groups.all}',
      );
    }
  }
}
```

### Usage

```dart
// Define groups for a bloc
class CounterGroups extends RebuildGroups {
  static const display = {'counter_display'};
  static const buttons = {'counter_buttons'};
  static const status = {'counter_status'};

  @override
  Set<String> get all => {...display, ...buttons, ...status};
}

// Use in bloc
class CounterBloc extends JuiceBloc<CounterState>
    with RebuildGroupValidation<CounterGroups> {

  @override
  final groups = CounterGroups();

  // ...
}

// Use in use case - compile-time safe
emitUpdate(
  newState: newState,
  groupsToRebuild: CounterGroups.display, // Type-safe!
);

// Use in widget - compile-time safe
class CounterDisplay extends StatelessJuiceWidget<CounterBloc> {
  CounterDisplay({super.groups = CounterGroups.display}); // Type-safe!
}
```

### Analyzer Plugin (Optional)

```yaml
# analysis_options.yaml
analyzer:
  plugins:
    - juice_lints

juice_lints:
  rules:
    unused_rebuild_group: warning      # Group defined but never used
    undefined_rebuild_group: error     # Group used but not defined
    mismatched_bloc_group: error       # Widget uses group from wrong bloc
```

---

## 6. DevTools Extension

### Problem
No visibility into bloc state, event flow, or rebuild patterns during development.

### Solution
Create a Flutter DevTools extension.

### Features

```
┌─────────────────────────────────────────────────────────────────────┐
│ Juice Inspector                                          [Pause] [Clear] │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│ ┌─ Active Blocs ──────────────────────────────────────────────────┐ │
│ │ ▼ CounterBloc                                        [Inspect]  │ │
│ │   State: CounterState(count: 5)                                 │ │
│ │   Status: UpdatingStatus                                        │ │
│ │   Groups: counter_display                                       │ │
│ │                                                                  │ │
│ │ ▶ TodoBloc                                           [Inspect]  │ │
│ │ ▶ SettingsBloc                                       [Inspect]  │ │
│ └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│ ┌─ Event Stream ──────────────────────────────────────────────────┐ │
│ │ 12:01:05.123  IncrementEvent → CounterBloc                      │ │
│ │   └─ IncrementUseCase                                           │ │
│ │   └─ UpdatingStatus (groups: counter_display)                   │ │
│ │   └─ Rebuilt: CounterWidget, CounterStatus                      │ │
│ │                                                                  │ │
│ │ 12:01:03.456  AddTodoEvent → TodoBloc                           │ │
│ │   └─ AddTodoUseCase                                             │ │
│ │   └─ UpdatingStatus (groups: todo_list)                         │ │
│ │   └─ Rebuilt: TodoListWidget                                    │ │
│ └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│ ┌─ Widget Tree (Rebuild Groups) ──────────────────────────────────┐ │
│ │ MyApp                                                            │ │
│ │ ├─ CounterPage                                                   │ │
│ │ │  ├─ CounterWidget [counter_display] ← Last: 12:01:05          │ │
│ │ │  ├─ CounterButtons [opt-out]                                  │ │
│ │ │  └─ CounterStatus [counter_display, counter_status]           │ │
│ │ └─ TodoPage                                                      │ │
│ │    └─ TodoListWidget [todo_list]                                │ │
│ └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│ ┌─ Time Travel ───────────────────────────────────────────────────┐ │
│ │ [◀◀] [◀] ──────────●────────────────────────────── [▶] [▶▶]    │ │
│ │        State 5 of 12                              [Export JSON] │ │
│ └──────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### Implementation Approach

1. Create `devtools_extension/` package
2. Use `package:devtools_extensions` for integration
3. Communicate with app via `postMessage` / `dart:developer` Service Protocol
4. Store state history for time-travel debugging

### Package Structure

```
juice_devtools/
├── lib/
│   └── juice_devtools.dart
├── extension/
│   └── devtools/
│       ├── build/           # Built extension
│       └── config.yaml      # DevTools config
└── pubspec.yaml
```

---

## 7. Flexible Widget Integration

### Problem
Must extend `StatelessJuiceWidget` or `JuiceWidgetState`, can't mix with other patterns.

### Solution
Add mixin-based approach and builder widgets.

### Implementation: Mixin

```dart
// lib/src/ui/src/juice_mixin.dart

/// Mixin for adding Juice bloc integration to any StatefulWidget.
mixin JuiceMixin<TBloc extends JuiceBloc> on State<StatefulWidget> {
  StreamSubscription<StreamStatus>? _subscription;
  Set<String> get rebuildGroups => {'*'};

  /// The bloc instance, resolved from scope or global resolver
  TBloc get bloc {
    final scopeResolver = JuiceScope.maybeOf(context);
    if (scopeResolver != null) {
      return scopeResolver.resolve<TBloc>();
    }
    return GlobalBlocResolver().resolver.resolve<TBloc>();
  }

  /// Subscribe to bloc updates. Call in initState.
  @protected
  void subscribeToBloc() {
    _subscription = bloc.stream
        .where((status) => !denyRebuild(
              event: status.event,
              key: widget.key,
              rebuildGroups: rebuildGroups,
            ))
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// Unsubscribe from bloc. Called automatically in dispose.
  @protected
  void unsubscribeFromBloc() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    unsubscribeFromBloc();
    super.dispose();
  }
}

/// Multi-bloc mixin variant
mixin JuiceMixin2<TBloc1 extends JuiceBloc, TBloc2 extends JuiceBloc>
    on State<StatefulWidget> {
  // Similar implementation with MergeStream
}
```

### Implementation: Builder Widget

```dart
// lib/src/ui/src/juice_builder.dart

/// Builder widget for reactive bloc state, similar to BlocBuilder.
class JuiceBuilder<TBloc extends JuiceBloc> extends StatefulWidget {
  final Widget Function(BuildContext context, TBloc bloc, StreamStatus status) builder;
  final Set<String> groups;
  final BlocDependencyResolver? resolver;
  final bool Function(StreamStatus status)? buildWhen;

  const JuiceBuilder({
    super.key,
    required this.builder,
    this.groups = const {'*'},
    this.resolver,
    this.buildWhen,
  });

  @override
  State<JuiceBuilder<TBloc>> createState() => _JuiceBuilderState<TBloc>();
}

class _JuiceBuilderState<TBloc extends JuiceBloc>
    extends State<JuiceBuilder<TBloc>> {
  late TBloc _bloc;
  late StreamStatus _status;
  StreamSubscription<StreamStatus>? _subscription;

  @override
  void initState() {
    super.initState();
    _bloc = _resolveBloc();
    _status = _bloc.currentStatus;
    _subscribe();
  }

  TBloc _resolveBloc() {
    if (widget.resolver != null) {
      return widget.resolver!.resolve<TBloc>();
    }
    final scopeResolver = JuiceScope.maybeOf(context);
    if (scopeResolver != null) {
      return scopeResolver.resolve<TBloc>();
    }
    return GlobalBlocResolver().resolver.resolve<TBloc>();
  }

  void _subscribe() {
    _subscription = _bloc.stream.where((status) {
      if (denyRebuild(
        event: status.event,
        key: widget.key,
        rebuildGroups: widget.groups,
      )) {
        return false;
      }
      if (widget.buildWhen != null && !widget.buildWhen!(status)) {
        return false;
      }
      return true;
    }).listen((status) {
      setState(() => _status = status);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _bloc, _status);
  }
}

/// Multi-bloc builder
class JuiceBuilder2<TBloc1 extends JuiceBloc, TBloc2 extends JuiceBloc>
    extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    TBloc1 bloc1,
    TBloc2 bloc2,
    StreamStatus status,
  ) builder;
  final Set<String> groups;

  // Similar implementation...
}
```

### Usage

```dart
// Mixin approach - works with any StatefulWidget
class MyComplexWidget extends StatefulWidget {
  @override
  State<MyComplexWidget> createState() => _MyComplexWidgetState();
}

class _MyComplexWidgetState extends State<MyComplexWidget>
    with JuiceMixin<CounterBloc>, SingleTickerProviderStateMixin {

  late AnimationController _controller;

  @override
  Set<String> get rebuildGroups => CounterGroups.display;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    subscribeToBloc();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Text('Count: ${bloc.state.count}');
      },
    );
  }
}

// Builder approach - inline, no custom class needed
Widget build(BuildContext context) {
  return JuiceBuilder<CounterBloc>(
    groups: CounterGroups.display,
    builder: (context, bloc, status) {
      return Text('Count: ${bloc.state.count}');
    },
  );
}

// Multi-bloc builder
Widget build(BuildContext context) {
  return JuiceBuilder2<CounterBloc, SettingsBloc>(
    groups: {...CounterGroups.display, ...SettingsGroups.theme},
    builder: (context, counterBloc, settingsBloc, status) {
      return Text(
        'Count: ${counterBloc.state.count}',
        style: TextStyle(
          color: settingsBloc.state.isDarkMode ? Colors.white : Colors.black,
        ),
      );
    },
  );
}
```

---

## 8. Code Generation

### Problem
Boilerplate for blocs, states, events, and use cases is repetitive.

### Solution
Create a `build_runner` code generator.

### Annotation-Based API

```dart
// lib/src/annotations/juice_annotations.dart

/// Marks a class for bloc code generation
class JuiceBlocAnnotation {
  final List<String> groups;
  const JuiceBlocAnnotation({this.groups = const []});
}
const juiceBloc = JuiceBlocAnnotation;

/// Marks a method as a use case handler
class UseCaseAnnotation {
  final Type eventType;
  final bool stateful;
  const UseCaseAnnotation({required this.eventType, this.stateful = false});
}
const useCase = UseCaseAnnotation;

/// Marks a field as the initial state
class InitialStateAnnotation {
  const InitialStateAnnotation();
}
const initialState = InitialStateAnnotation;
```

### Usage

```dart
// counter_bloc.dart
import 'package:juice/juice.dart';

part 'counter_bloc.g.dart';

@juiceBloc(groups: ['display', 'buttons'])
abstract class _CounterBloc {
  @initialState
  CounterState get initial => CounterState(count: 0);

  @useCase(eventType: IncrementEvent)
  Future<CounterState> increment(IncrementEvent event, CounterState state) async {
    return state.copyWith(count: state.count + 1);
  }

  @useCase(eventType: DecrementEvent)
  Future<CounterState> decrement(DecrementEvent event, CounterState state) async {
    return state.copyWith(count: state.count - 1);
  }

  @useCase(eventType: ResetEvent)
  Future<CounterState> reset(ResetEvent event, CounterState state) async {
    return state.copyWith(count: 0);
  }
}

// Events (could also be generated)
class IncrementEvent extends EventBase {}
class DecrementEvent extends EventBase {}
class ResetEvent extends EventBase {}
```

### Generated Code

```dart
// counter_bloc.g.dart
part of 'counter_bloc.dart';

class CounterBloc extends JuiceBloc<CounterState> implements _CounterBloc {
  CounterBloc() : super(
    CounterState(count: 0),
    [
      () => UseCaseBuilder(
        typeOfEvent: IncrementEvent,
        useCaseGenerator: () => _IncrementUseCase(),
      ),
      () => UseCaseBuilder(
        typeOfEvent: DecrementEvent,
        useCaseGenerator: () => _DecrementUseCase(),
      ),
      () => UseCaseBuilder(
        typeOfEvent: ResetEvent,
        useCaseGenerator: () => _ResetUseCase(),
      ),
    ],
    [],
  );

  @override
  CounterState get initial => CounterState(count: 0);

  @override
  Future<CounterState> increment(IncrementEvent event, CounterState state) async {
    return state.copyWith(count: state.count + 1);
  }

  @override
  Future<CounterState> decrement(DecrementEvent event, CounterState state) async {
    return state.copyWith(count: state.count - 1);
  }

  @override
  Future<CounterState> reset(ResetEvent event, CounterState state) async {
    return state.copyWith(count: 0);
  }
}

// Type-safe groups
abstract class CounterGroups {
  static const display = {'display'};
  static const buttons = {'buttons'};
  static const all = {'display', 'buttons'};
}

class _IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    final newState = await bloc.increment(event, bloc.state);
    emitUpdate(newState: newState, groupsToRebuild: CounterGroups.display);
  }
}

class _DecrementUseCase extends BlocUseCase<CounterBloc, DecrementEvent> {
  @override
  Future<void> execute(DecrementEvent event) async {
    final newState = await bloc.decrement(event, bloc.state);
    emitUpdate(newState: newState, groupsToRebuild: CounterGroups.display);
  }
}

class _ResetUseCase extends BlocUseCase<CounterBloc, ResetEvent> {
  @override
  Future<void> execute(ResetEvent event) async {
    final newState = await bloc.reset(event, bloc.state);
    emitUpdate(newState: newState, groupsToRebuild: CounterGroups.display);
  }
}
```

### Package Structure

```
juice_generator/
├── lib/
│   ├── juice_generator.dart
│   ├── src/
│   │   ├── bloc_generator.dart
│   │   ├── use_case_generator.dart
│   │   └── groups_generator.dart
│   └── builder.dart
├── pubspec.yaml
└── build.yaml
```

---

## Implementation Priority

| Priority | Improvement | Effort | Impact |
|----------|-------------|--------|--------|
| 1 | Type-Safe Rebuild Groups | Low | High |
| 2 | Inline Use Cases | Low | High |
| 3 | JuiceBuilder Widget | Low | Medium |
| 4 | JuiceMixin | Low | Medium |
| 5 | JuiceScope | Medium | High |
| 6 | Event Tracing | Medium | Medium |
| 7 | Code Generation | High | High |
| 8 | DevTools Extension | High | Medium |

---

## Migration Path

All improvements are designed to be **additive and backward-compatible**:

1. Existing code continues to work unchanged
2. New features are opt-in
3. Deprecation warnings guide migration over time
4. Global resolver remains available alongside scoped registration

---

## Next Steps

1. [ ] Create issues for each improvement
2. [ ] Prioritize based on user feedback
3. [ ] Implement type-safe rebuild groups (quick win)
4. [ ] Implement inline use cases (quick win)
5. [ ] Design and implement JuiceScope
6. [ ] Build DevTools extension prototype
