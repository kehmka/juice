// ignore_for_file: deprecated_member_use_from_same_package

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

  /// Runs [action] while tracking a single entity's async status in your state,
  /// guaranteeing the entity is set to **waiting** before, **idle** after — or
  /// **failure** if [action] throws (cleanup happens even on error, killing the
  /// stuck-spinner footgun). The per-entity analogue of the
  /// `emitWaiting → emitUpdate/emitFailure` lifecycle.
  ///
  /// [read] locates the [EntityStatuses] field in the current state and [write]
  /// returns a new state with an updated map — so a bloc may track several
  /// independent status maps, and [action]'s own emits compose (each step
  /// re-reads the latest state):
  ///
  /// ```dart
  /// Future<void> execute(RereadEvent e) => guardEntity<String, void>(
  ///   e.id,
  ///   read: (b) => b.state.mediaStatus,
  ///   write: (s) => bloc.state.copyWith(mediaStatus: s),
  ///   groupsToRebuild: {Groups.review},
  ///   action: () async { /* the risky work; may emit + may throw */ },
  /// );
  /// ```
  ///
  /// Returns the action's result, or `null` if it threw (unless
  /// [rethrowOnError]).
  Future<T?> guardEntity<K, T>(
    K key, {
    required EntityStatuses<K> Function(TBloc bloc) read,
    required BlocState Function(EntityStatuses<K> statuses) write,
    required Future<T> Function() action,
    Set<String>? groupsToRebuild,
    bool rethrowOnError = false,
  }) async {
    emitUpdate(
      newState: write(read(bloc).waiting(key)),
      groupsToRebuild: groupsToRebuild,
    );
    try {
      final result = await action();
      emitUpdate(
        newState: write(read(bloc).idle(key)),
        groupsToRebuild: groupsToRebuild,
      );
      return result;
    } catch (error, stackTrace) {
      logError(error, stackTrace);
      emitFailure(
        newState: write(read(bloc).failure(key, error)),
        groupsToRebuild: groupsToRebuild,
        error: error,
        errorStackTrace: stackTrace,
      );
      if (rethrowOnError) rethrow;
      return null;
    }
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

/// Built-in use case that handles [UpdateEvent]s for navigation and status changes.
///
/// This use case is automatically registered with all blocs. It handles:
/// - Navigation triggers via aviator system
/// - Stream status changes (update/waiting/failure)
/// - Widget rebuild control via groups
///
/// **Note**: The [UpdateEvent.newState] parameter is deprecated. State changes
/// should go through dedicated use cases to maintain clean architecture.
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
