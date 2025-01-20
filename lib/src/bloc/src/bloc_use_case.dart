import 'package:juice/juice.dart';

/// Base class for bloc-specific use cases that provides logging and naming capabilities.
///
/// [TBloc] - The type of bloc this use case works with
/// [TEvent] - The type of event this use case handles
///
/// This abstract class provides common functionality for all bloc use cases including:
/// - Automatic use case naming
/// - Structured logging with context support
/// - Error tracking
abstract class BlocUseCase<TBloc extends JuiceBloc, TEvent extends EventBase>
    extends UseCase<TBloc, TEvent> {
  /// Name of the use case, automatically set from the runtime type
  late final String useCaseName;

  BlocUseCase() {
    useCaseName = runtimeType.toString();
  }

  /// Execute the use case logic for the given event.
  ///
  /// This method must be implemented by concrete use cases to define their behavior.
  @override
  Future<void> execute(TEvent event);

  /// Logs a message with the use case name as prefix.
  ///
  /// [message] - The message to log
  /// [level] - Optional log level, defaults to info
  /// [context] - Optional structured context data about the log entry
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    final enrichedContext = {
      'useCase': useCaseName,
      'bloc': bloc.runtimeType.toString(),
      ...?context,
    };

    JuiceLoggerConfig.logger.log(
      '[$useCaseName] $message',
      level: level,
      context: enrichedContext,
    );
  }

  /// Logs the current state with the use case name as prefix.
  ///
  /// [stateDescription] - Description of the state to log
  /// [context] - Optional structured context data about the state
  void logState(String stateDescription, {Map<String, dynamic>? context}) {
    final enrichedContext = {
      'useCase': useCaseName,
      'bloc': bloc.runtimeType.toString(),
      'state': bloc.state.toString(),
      ...?context,
    };

    JuiceLoggerConfig.logger.log(
      '[$useCaseName] State: $stateDescription',
      context: enrichedContext,
    );
  }

  /// Logs an error with stack trace and use case name as prefix.
  ///
  /// [error] - The error that occurred
  /// [stackTrace] - Stack trace of the error
  /// [context] - Optional structured context data about the error
  void logError(Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) {
    final enrichedContext = {
      'useCase': useCaseName,
      'bloc': bloc.runtimeType.toString(),
      'state': bloc.state.toString(),
      ...?context,
    };

    JuiceLoggerConfig.logger.logError(
      '[$useCaseName] Exception: $error',
      error,
      stackTrace,
      context: enrichedContext,
    );
  }
}

/// A special use case that handles state updates without requiring a dedicated use case.
///
/// WARNING: While convenient for prototyping and simple state updates, use with caution
/// in production code as it bypasses the explicit use case pattern.
///
/// This use case is automatically registered with all blocs and handles [UpdateEvent]s.
/// It can:
/// - Update the bloc state
/// - Trigger navigation
/// - Control widget rebuilds
/// - Set different stream status types (update/waiting/failure)
class UpdateUseCase<TBloc extends JuiceBloc>
    extends BlocUseCase<TBloc, UpdateEvent> {
  @override
  Future<void> execute(UpdateEvent event) async {
    switch (event.resetStatusTo) {
      case ResetStreamType.onUpdate:
        emitUpdate(
            newState: event.newState ?? bloc.state,
            groupsToRebuild: event.groupsToRebuild,
            aviatorName: event.aviatorName,
            aviatorArgs: event.aviatorArgs);
        break;
      case ResetStreamType.onFailure:
        emitFailure(
            newState: event.newState ?? bloc.state,
            groupsToRebuild: event.groupsToRebuild,
            aviatorName: event.aviatorName,
            aviatorArgs: event.aviatorArgs);
        break;
      case ResetStreamType.onWaiting:
        emitWaiting(
            newState: event.newState ?? bloc.state,
            groupsToRebuild: event.groupsToRebuild,
            aviatorName: event.aviatorName,
            aviatorArgs: event.aviatorArgs);
        break;
    }
  }
}
