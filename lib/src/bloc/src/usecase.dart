import '../bloc.dart';

/// Base class for implementing use cases in the Juice framework.
///
/// A use case represents a single unit of business logic that can be executed
/// in response to an event. It provides methods for emitting different types
/// of state updates and handling navigation.
///
/// Type Parameters:
/// * [TBloc] - The type of bloc this use case works with
/// * [TEvent] - The type of event this use case handles
///
/// Example:
/// ```dart
/// class FetchUserUseCase extends UseCase<UserBloc, FetchUserEvent> {
///   @override
///   Future<void> execute(FetchUserEvent event) async {
///     try {
///       emitWaiting(); // Show loading state
///       final user = await userRepository.fetchUser(event.userId);
///       if (event is CancellableEvent && event.isCancelled) {
///         emitCancel(); // Show cancellation state
///         return;
///       }
///       emitUpdate(newState: UserState(user: user));
///     } catch (e) {
///       emitFailure(); // Show error state
///     }
///   }
/// }
/// ```
abstract class UseCase<TBloc extends JuiceBloc, TEvent extends EventBase> {
  /// Executes the business logic for this use case.
  ///
  /// This is the main method that should be implemented by concrete use cases
  /// to define their behavior.
  Future<void> execute(TEvent event);

  /// Reference to the bloc that owns this use case.
  /// Set automatically by the framework via [setBloc].
  late TBloc bloc;

  /// Sets the bloc reference for this use case.
  ///
  /// Called by the framework during use case execution setup.
  /// Performs a type-safe cast from JuiceBloc to the specific TBloc type.
  void setBloc(JuiceBloc blocInstance) {
    bloc = blocInstance as TBloc;
  }

  /// Emits an update state to indicate successful operation completion.
  ///
  /// Parameters:
  /// * [newState] - Optional new state to set
  /// * [aviatorName] - Optional navigation target
  /// * [aviatorArgs] - Optional navigation arguments
  /// * [groupsToRebuild] - Optional set of widget groups to rebuild
  /// * [skipIfSame] - If true, skips emission when newState equals current state
  late void Function(
      {BlocState? newState,
      String? aviatorName,
      Map<String, dynamic>? aviatorArgs,
      Set<String>? groupsToRebuild,
      bool skipIfSame}) emitUpdate;

  /// Emits a failure state to indicate operation failure.
  ///
  /// Parameters:
  /// * [newState] - Optional new state to set
  /// * [aviatorName] - Optional navigation target
  /// * [aviatorArgs] - Optional navigation arguments
  /// * [groupsToRebuild] - Optional set of widget groups to rebuild
  /// * [error] - The error that caused the failure
  /// * [errorStackTrace] - The stack trace where the error occurred
  late void Function(
      {BlocState? newState,
      String? aviatorName,
      Map<String, dynamic>? aviatorArgs,
      Set<String>? groupsToRebuild,
      Object? error,
      StackTrace? errorStackTrace}) emitFailure;

  /// Emits a waiting state to indicate operation in progress.
  ///
  /// Parameters match [emitUpdate].
  late void Function(
      {BlocState? newState,
      String? aviatorName,
      Map<String, dynamic>? aviatorArgs,
      Set<String>? groupsToRebuild}) emitWaiting;

  /// Emits a cancellation state to indicate the operation was cancelled.
  ///
  /// This should be used when a [CancellableEvent] is cancelled during execution.
  /// Parameters match [emitUpdate].
  late void Function(
      {BlocState? newState,
      String? aviatorName,
      Map<String, dynamic>? aviatorArgs,
      Set<String>? groupsToRebuild}) emitCancel;

  /// Emits a raw event without changing state.
  ///
  /// [event] - The event to emit
  late void Function({EventBase? event}) emitEvent;

  /// Performs cleanup when the use case is no longer needed.
  ///
  /// Override this method to clean up any resources used by the use case.
  void close() {}
}

/// A No-Operation Use Case that performs no action.
///
/// Useful as a placeholder or default when no specific use case behavior
/// is needed.
class NoOpUseCase extends UseCase {
  @override
  Future<void> execute(event) async {
    // Do nothing
  }
}

/// Generator function that produces a [NoOpUseCase].
///
/// Can be used as a default use case generator when no specific behavior
/// is needed.
UseCaseGenerator noOpUseCaseGenerator = () => NoOpUseCase();
