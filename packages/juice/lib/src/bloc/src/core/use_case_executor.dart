import 'dart:async';
import 'package:logger/web.dart' show Level;
import '../bloc_state.dart';
import '../bloc_event.dart';
import '../cancellable_event.dart';
import '../juice_bloc.dart';
import '../usecase.dart';
import '../juice_logger.dart';
import 'restartable_run.dart';
import 'type_names.dart';
import '../telemetry.dart';
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

  /// Emits an updating status.
  ///
  /// [skipIfSame] - If true, skips emission when newState equals current state.
  final void Function(TState? newState, Set<String>? groups, {bool skipIfSame})
      emitUpdate;

  /// Emits a waiting status.
  final void Function(TState? newState, Set<String>? groups) emitWaiting;

  /// Emits a failure status.
  ///
  /// [error] and [errorStackTrace] are stored in FailureStatus for debugging.
  final void Function(TState? newState, Set<String>? groups,
      {Object? error, StackTrace? errorStackTrace}) emitFailure;

  /// Emits a canceling status.
  final void Function(TState? newState, Set<String>? groups) emitCancel;

  /// Emits the event without state change.
  final void Function(EventBase? event) emitEvent;

  /// Triggers navigation (fire-and-forget).
  ///
  /// If the aviator's navigation is async, this will not wait for completion.
  final void Function(String? aviator, Map<String, dynamic>? args) navigate;

  const UseCaseContext({
    required this.bloc,
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

  /// Monotonic id stamped on a use case's start and end log entries, so a
  /// telemetry consumer can pair them into a span even when two events of
  /// the SAME type overlap under `EventConcurrency.concurrent`. Process-wide
  /// (static) on purpose: uniqueness must hold across blocs.
  static int _nextExecutionId = 0;

  /// Executes a use case for the given event.
  ///
  /// Creates a use case instance from the builder, wires it with context,
  /// and executes it. Errors are logged and passed to the error handler.
  ///
  /// Every execution logs exactly two structured entries: the
  /// `use_case_execution` start, and — sharing its `executionId` — either
  /// `use_case_completed` (with `elapsedMicros`) or `use_case_error` (with
  /// `elapsedMicros` when the start was logged). A span consumer closes on
  /// whichever arrives. Below the telemetry floor only the error line is
  /// built.
  Future<void> execute(UseCaseBuilderBase builder, EventBase event) async {
    final executionId = _nextExecutionId++;
    // Built only when a line will carry them: the two type names and the
    // stopwatch are the span's content, not the send's.
    final chatter = JuiceLoggerConfig.logs(Level.info);
    final stopwatch = chatter ? (Stopwatch()..start()) : null;
    final run = RestartableRun.current;
    UseCase? useCase;
    try {
      // The generator and the context are inside the try: a throwing
      // generator (a DI lookup) is a use-case error, not a silent miss.
      useCase = builder.generator();
      final context = _contextFactory(event);
      if (chatter) {
        _logger.record(JuiceTelemetry(
          JuiceTelemetryKind.useCaseStarted,
          useCase: typeName(useCase.runtimeType),
          event: typeName(event.runtimeType),
          executionId: executionId,
        ));
      }
      _wireUseCase(useCase, context);
      await useCase.execute(event);
      run?.complete();
      if (chatter) {
        _logger.record(JuiceTelemetry(
          JuiceTelemetryKind.useCaseCompleted,
          useCase: typeName(useCase.runtimeType),
          event: typeName(event.runtimeType),
          executionId: executionId,
          elapsedMicros: stopwatch!.elapsedMicroseconds,
          superseded: run?.isSuperseded ?? false,
        ));
      }
    } catch (error, stackTrace) {
      run?.complete();
      _logger.record(JuiceTelemetry(
        JuiceTelemetryKind.useCaseFailed,
        // A generator that threw left no use case: the builder names it.
        useCase: typeName((useCase ?? builder).runtimeType),
        event: typeName(event.runtimeType),
        executionId: executionId,
        elapsedMicros: stopwatch?.elapsedMicroseconds,
        superseded: run?.isSuperseded ?? false,
        error: error,
        stackTrace: stackTrace,
      ));
      _onError(error, stackTrace, event);
    } finally {
      // The work is over: a still-running timeout must not fire later and
      // mark this completed event timed out.
      if (event is TimeoutSupport) event.settleTimeout();
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
      bool skipIfSame = false,
    }) {
      context.emitUpdate(newState as TState?, groupsToRebuild,
          skipIfSame: skipIfSame);
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
      Object? error,
      StackTrace? errorStackTrace,
    }) {
      context.emitFailure(newState as TState?, groupsToRebuild,
          error: error, errorStackTrace: errorStackTrace);
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
    useCase.navigate = context.navigate;
  }
}
