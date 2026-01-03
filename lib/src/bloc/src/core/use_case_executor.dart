import 'dart:async';
import '../bloc_state.dart';
import '../bloc_event.dart';
import '../juice_bloc.dart';
import '../usecase.dart';
import '../juice_logger.dart';
import '../use_case_builders/use_case_builder.dart';

/// Context provided to use cases for state emission.
///
/// This class encapsulates all the dependencies a use case needs to execute,
/// including the bloc reference and emit functions. The context is created
/// fresh for each event execution, capturing the event for emit operations.
///
/// Example:
/// ```dart
/// final context = UseCaseContext(
///   bloc: myBloc,
///   getState: () => myBloc.state,
///   getOldState: () => myBloc.oldState,
///   emitUpdate: (newState, groups) => statusEmitter.emitUpdate(...),
///   emitWaiting: (newState, groups) => statusEmitter.emitWaiting(...),
///   emitFailure: (newState, groups) => statusEmitter.emitFailure(...),
///   emitCancel: (newState, groups) => statusEmitter.emitCancel(...),
///   navigate: (aviator, args) => aviatorManager.navigate(...),
/// );
/// ```
class UseCaseContext<TBloc, TState extends BlocState> {
  /// The bloc instance.
  final TBloc bloc;

  /// Returns the current state.
  final TState Function() getState;

  /// Returns the previous state.
  final TState Function() getOldState;

  /// Emits an updating status.
  final void Function(TState? newState, Set<String>? groups) emitUpdate;

  /// Emits a waiting status.
  final void Function(TState? newState, Set<String>? groups) emitWaiting;

  /// Emits a failure status.
  final void Function(TState? newState, Set<String>? groups) emitFailure;

  /// Emits a canceling status.
  final void Function(TState? newState, Set<String>? groups) emitCancel;

  /// Emits the event without state change.
  final void Function(EventBase? event) emitEvent;

  /// Triggers navigation.
  final void Function(String? aviator, Map<String, dynamic>? args) navigate;

  const UseCaseContext({
    required this.bloc,
    required this.getState,
    required this.getOldState,
    required this.emitUpdate,
    required this.emitWaiting,
    required this.emitFailure,
    required this.emitCancel,
    required this.emitEvent,
    required this.navigate,
  });
}

/// Executes use cases with injected context.
///
/// The executor is responsible for:
/// - Creating use case instances from builders
/// - Wiring use case dependencies (bloc, emit functions)
/// - Executing use cases and handling errors
///
/// Example:
/// ```dart
/// final executor = UseCaseExecutor(
///   contextFactory: (event) => UseCaseContext(...),
///   onError: (error, stack, event) => handleError(error),
///   logger: logger,
/// );
///
/// await executor.execute(builder, event);
/// ```
class UseCaseExecutor<TBloc, TState extends BlocState> {
  /// Creates a UseCaseExecutor.
  ///
  /// [contextFactory] creates a fresh context for each event execution.
  /// [onError] is called when use case execution fails.
  /// [logger] is used for logging execution details.
  UseCaseExecutor({
    required UseCaseContext<TBloc, TState> Function(EventBase event)
        contextFactory,
    required void Function(Object error, StackTrace stack, EventBase event)
        onError,
    required JuiceLogger logger,
  })  : _contextFactory = contextFactory,
        _onError = onError,
        _logger = logger;

  final UseCaseContext<TBloc, TState> Function(EventBase event) _contextFactory;
  final void Function(Object error, StackTrace stack, EventBase event) _onError;
  final JuiceLogger _logger;

  /// Executes a use case for the given event.
  ///
  /// Creates a use case instance from the builder, wires it with context,
  /// and executes it. Errors are logged and passed to the error handler.
  Future<void> execute(UseCaseBuilderBase builder, EventBase event) async {
    final useCase = builder.generator();
    final context = _contextFactory(event);

    _logger.log('Executing use case', context: {
      'type': 'use_case_execution',
      'useCase': useCase.runtimeType.toString(),
      'event': event.runtimeType.toString(),
    });

    _wireUseCase(useCase, context);

    try {
      await useCase.execute(event);
    } catch (error, stackTrace) {
      _logger.logError(
        'Use case execution failed',
        error,
        stackTrace,
        context: {
          'type': 'use_case_error',
          'useCase': useCase.runtimeType.toString(),
          'event': event.runtimeType.toString(),
        },
      );
      _onError(error, stackTrace, event);
    }
  }

  /// Wires a use case with its context dependencies.
  void _wireUseCase(UseCase useCase, UseCaseContext<TBloc, TState> context) {
    // Set the bloc reference via the type-safe setBloc method.
    // This avoids unsafe dynamic casts while still supporting generic bloc types.
    useCase.setBloc(context.bloc as JuiceBloc);

    useCase.emitUpdate = ({
      BlocState? newState,
      Set<String>? groupsToRebuild,
      String? aviatorName,
      Map<String, dynamic>? aviatorArgs,
    }) {
      context.emitUpdate(newState as TState?, groupsToRebuild);
      context.navigate(aviatorName, aviatorArgs);
    };

    useCase.emitWaiting = ({
      BlocState? newState,
      Set<String>? groupsToRebuild,
      String? aviatorName,
      Map<String, dynamic>? aviatorArgs,
    }) {
      context.emitWaiting(newState as TState?, groupsToRebuild);
      context.navigate(aviatorName, aviatorArgs);
    };

    useCase.emitFailure = ({
      BlocState? newState,
      Set<String>? groupsToRebuild,
      String? aviatorName,
      Map<String, dynamic>? aviatorArgs,
    }) {
      context.emitFailure(newState as TState?, groupsToRebuild);
      context.navigate(aviatorName, aviatorArgs);
    };

    useCase.emitCancel = ({
      BlocState? newState,
      Set<String>? groupsToRebuild,
      String? aviatorName,
      Map<String, dynamic>? aviatorArgs,
    }) {
      context.emitCancel(newState as TState?, groupsToRebuild);
      context.navigate(aviatorName, aviatorArgs);
    };

    useCase.emitEvent = ({EventBase? event}) => context.emitEvent(event);
  }
}
