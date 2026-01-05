import 'package:juice/juice.dart';
import '../features_showcase_bloc.dart';
import '../features_showcase_events.dart';

/// Simulates an API call that can succeed or fail.
///
/// Demonstrates:
/// - WaitingStatus while async operation is in progress
/// - NetworkException for typed error handling
/// - FailureStatus with error context (error + stackTrace)
/// - Proper error handling with emitFailure
class SimulateApiUseCase
    extends BlocUseCase<FeaturesShowcaseBloc, SimulateApiCallEvent> {
  @override
  Future<void> execute(SimulateApiCallEvent event) async {
    // Show loading state
    emitWaiting(
      newState: bloc.state.copyWith(
        isLoading: true,
        activityLog: [
          ...bloc.state.activityLog,
          'API call started...',
        ],
      ),
      groupsToRebuild: {'status', 'activity'},
    );

    try {
      // Simulate network delay
      await Future.delayed(const Duration(seconds: 1));

      if (event.shouldFail) {
        // Throw a typed JuiceException
        throw const NetworkException(
          'Server returned 500 Internal Server Error',
          statusCode: 500,
        );
      }

      // Success!
      final newApiCallCount = bloc.state.apiCallCount + 1;
      emitUpdate(
        newState: bloc.state.copyWith(
          isLoading: false,
          apiCallCount: newApiCallCount,
          message: 'API call #$newApiCallCount successful!',
          clearError: true,
          activityLog: [
            ...bloc.state.activityLog,
            'API call #$newApiCallCount completed successfully',
          ],
        ),
        groupsToRebuild: {'status', 'message', 'activity'},
      );
    } on NetworkException catch (e, stackTrace) {
      // Handle typed network exception with full error context
      emitFailure(
        newState: bloc.state.copyWith(
          isLoading: false,
          lastError: e.message,
          activityLog: [
            ...bloc.state.activityLog,
            'API call failed: ${e.message}',
          ],
        ),
        groupsToRebuild: {'status', 'error', 'activity'},
        // These are passed to FailureStatus.error and FailureStatus.errorStackTrace
        error: e,
        errorStackTrace: stackTrace,
      );
    } catch (e, stackTrace) {
      // Handle unexpected errors
      emitFailure(
        newState: bloc.state.copyWith(
          isLoading: false,
          lastError: 'Unexpected error: $e',
          activityLog: [
            ...bloc.state.activityLog,
            'Unexpected error occurred',
          ],
        ),
        groupsToRebuild: {'status', 'error', 'activity'},
        error: e,
        errorStackTrace: stackTrace,
      );
    }
  }
}
