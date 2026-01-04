import '../../../bloc.dart';
import '../../../../ui/src/rebuild_group.dart';

/// Emitter for inline use case handlers.
///
/// Provides a clean API for emitting state changes:
/// ```dart
/// ctx.emit.update(newState: newState, groups: {CounterGroups.counter});
/// ctx.emit.waiting(groups: {CounterGroups.counter});
/// ```
class InlineEmitter<TState extends BlocState> {
  final void Function(TState? newState, Set<String>? groups) _emitUpdate;
  final void Function(TState? newState, Set<String>? groups) _emitWaiting;
  final void Function(TState? newState, Set<String>? groups) _emitFailure;
  final void Function(TState? newState, Set<String>? groups) _emitCancel;
  final void Function(String? aviator, Map<String, dynamic>? args) _navigate;

  const InlineEmitter({
    required void Function(TState? newState, Set<String>? groups) emitUpdate,
    required void Function(TState? newState, Set<String>? groups) emitWaiting,
    required void Function(TState? newState, Set<String>? groups) emitFailure,
    required void Function(TState? newState, Set<String>? groups) emitCancel,
    required void Function(String? aviator, Map<String, dynamic>? args) navigate,
  })  : _emitUpdate = emitUpdate,
        _emitWaiting = emitWaiting,
        _emitFailure = emitFailure,
        _emitCancel = emitCancel,
        _navigate = navigate;

  /// Emits an update status indicating successful operation.
  ///
  /// [newState] - Optional new state (uses current if null)
  /// [groups] - Rebuild groups (supports [RebuildGroup], enums, or strings)
  /// [aviatorName] - Optional navigation target
  /// [aviatorArgs] - Optional navigation arguments
  void update({
    TState? newState,
    Set<Object>? groups,
    String? aviatorName,
    Map<String, dynamic>? aviatorArgs,
  }) {
    _emitUpdate(newState, _convertGroups(groups));
    if (aviatorName != null) _navigate(aviatorName, aviatorArgs);
  }

  /// Emits a waiting status indicating operation in progress.
  void waiting({
    TState? newState,
    Set<Object>? groups,
    String? aviatorName,
    Map<String, dynamic>? aviatorArgs,
  }) {
    _emitWaiting(newState, _convertGroups(groups));
    if (aviatorName != null) _navigate(aviatorName, aviatorArgs);
  }

  /// Emits a failure status indicating operation failed.
  void failure({
    TState? newState,
    Set<Object>? groups,
    String? aviatorName,
    Map<String, dynamic>? aviatorArgs,
  }) {
    _emitFailure(newState, _convertGroups(groups));
    if (aviatorName != null) _navigate(aviatorName, aviatorArgs);
  }

  /// Emits a cancel status indicating operation was cancelled.
  void cancel({
    TState? newState,
    Set<Object>? groups,
    String? aviatorName,
    Map<String, dynamic>? aviatorArgs,
  }) {
    _emitCancel(newState, _convertGroups(groups));
    if (aviatorName != null) _navigate(aviatorName, aviatorArgs);
  }

  /// Converts Set<Object> to Set<String> for internal use.
  ///
  /// Supports:
  /// - [RebuildGroup] - uses `.name`
  /// - [String] - used directly
  /// - [Enum] - uses `.name`
  /// - Other objects - uses `.toString()`
  Set<String>? _convertGroups(Set<Object>? groups) {
    if (groups == null) return null;
    return groups.map((g) {
      if (g is RebuildGroup) return g.name;
      if (g is String) return g;
      if (g is Enum) return g.name;
      return g.toString();
    }).toSet();
  }
}

/// Context provided to inline use case handlers.
///
/// Provides typed access to bloc state and a clean emit API:
/// ```dart
/// handler: (ctx, event) async {
///   ctx.emit.update(
///     newState: ctx.state.copyWith(count: ctx.state.count + 1),
///     groups: {CounterGroups.counter},
///   );
/// }
/// ```
class InlineContext<TBloc extends JuiceBloc<TState>, TState extends BlocState> {
  /// The bloc instance.
  final TBloc bloc;

  /// Emitter for state changes.
  final InlineEmitter<TState> emit;

  /// The current state (typed).
  TState get state => bloc.state;

  /// The previous state (typed).
  TState get oldState => bloc.oldState;

  const InlineContext({
    required this.bloc,
    required this.emit,
  });
}

/// Handler signature for inline use cases.
///
/// ```dart
/// handler: (ctx, event) async {
///   ctx.emit.update(newState: ctx.state.copyWith(value: event.value));
/// }
/// ```
typedef InlineHandler<TBloc extends JuiceBloc<TState>, TState extends BlocState,
        TEvent extends EventBase>
    = Future<void> Function(InlineContext<TBloc, TState> ctx, TEvent event);

/// A use case builder for simple, stateless operations defined inline.
///
/// Use this for operations that:
/// - Have simple, synchronous logic
/// - Don't require I/O, caching, or retry logic
/// - Don't call multiple services
/// - Don't need multi-step flows
///
/// For complex operations, use a class-based [UseCase] instead.
///
/// ## Example
///
/// ```dart
/// class CounterBloc extends JuiceBloc<CounterState> {
///   CounterBloc() : super(CounterState(), [
///     // Simple increment - perfect for inline
///     () => InlineUseCaseBuilder<CounterBloc, CounterState, IncrementEvent>(
///       typeOfEvent: IncrementEvent,
///       handler: (ctx, event) async {
///         ctx.emit.update(
///           newState: ctx.state.copyWith(count: ctx.state.count + 1),
///           groups: {CounterGroups.counter},
///         );
///       },
///     ),
///
///     // Complex fetch - use class-based
///     () => UseCaseBuilder(
///       typeOfEvent: FetchDataEvent,
///       useCaseGenerator: () => FetchDataUseCase(),
///     ),
///   ]);
/// }
/// ```
///
/// ## When to Graduate to Class-Based
///
/// If your handler involves any of these, use a class-based [UseCase]:
/// - I/O operations (network, file, database)
/// - Caching or memoization
/// - Retry logic or error recovery
/// - Parsing or complex transformations
/// - Multi-step flows
/// - Calling more than one service
class InlineUseCaseBuilder<TBloc extends JuiceBloc<TState>,
        TState extends BlocState, TEvent extends EventBase>
    implements UseCaseBuilderBase {
  /// Creates an inline use case builder.
  ///
  /// [typeOfEvent] - The event type this handler responds to
  /// [handler] - The inline handler function
  /// [initialEventBuilder] - Optional builder for initial event on bloc start
  InlineUseCaseBuilder({
    required this.typeOfEvent,
    required this.handler,
    UseCaseEventBuilder? initialEventBuilder,
  }) : _initialEventBuilder = initialEventBuilder;

  /// The event type this use case handles.
  final Type typeOfEvent;

  /// The inline handler function.
  final InlineHandler<TBloc, TState, TEvent> handler;

  final UseCaseEventBuilder? _initialEventBuilder;

  @override
  Type get eventType => typeOfEvent;

  @override
  UseCaseEventBuilder? get initialEventBuilder => _initialEventBuilder;

  @override
  UseCaseGenerator get generator => () => _InlineUseCase<TBloc, TState, TEvent>(
        handler: handler,
      );

  @override
  Future<void> close() async {
    // No resources to clean up
  }
}

/// Internal use case wrapper that executes the inline handler.
class _InlineUseCase<TBloc extends JuiceBloc<TState>, TState extends BlocState,
    TEvent extends EventBase> extends UseCase<TBloc, TEvent> {
  final InlineHandler<TBloc, TState, TEvent> handler;

  _InlineUseCase({required this.handler});

  @override
  Future<void> execute(TEvent event) async {
    final emitter = InlineEmitter<TState>(
      emitUpdate: (newState, groups) => emitUpdate(
        newState: newState,
        groupsToRebuild: groups,
      ),
      emitWaiting: (newState, groups) => emitWaiting(
        newState: newState,
        groupsToRebuild: groups,
      ),
      emitFailure: (newState, groups) => emitFailure(
        newState: newState,
        groupsToRebuild: groups,
      ),
      emitCancel: (newState, groups) => emitCancel(
        newState: newState,
        groupsToRebuild: groups,
      ),
      navigate: (aviator, args) => emitUpdate(
        aviatorName: aviator,
        aviatorArgs: args,
      ),
    );

    final context = InlineContext<TBloc, TState>(
      bloc: bloc,
      emit: emitter,
    );

    await handler(context, event);
  }
}
