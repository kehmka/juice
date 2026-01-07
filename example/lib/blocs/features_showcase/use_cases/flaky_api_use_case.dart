import 'package:juice/juice.dart';

import '../features_showcase_bloc.dart';
import '../features_showcase_events.dart';

/// Use case that simulates a flaky API call.
///
/// This use case will fail [FlakyApiEvent.failuresBeforeSuccess] times,
/// then succeed. Used to demonstrate [RetryableUseCaseBuilder].
class FlakyApiUseCase
    extends BlocUseCase<FeaturesShowcaseBloc, FlakyApiEvent> {
  @override
  Future<void> execute(FlakyApiEvent event) async {
    final currentAttempt = bloc.state.retryAttempt + 1;
    final shouldFail = currentAttempt <= event.failuresBeforeSuccess;

    // Update attempt counter
    emitUpdate(
      newState: bloc.state.copyWith(
        retryAttempt: currentAttempt,
        retryStatus: 'retrying',
        activityLog: [
          ...bloc.state.activityLog,
          'Flaky API attempt $currentAttempt${shouldFail ? " (will fail)" : " (will succeed)"}',
        ],
      ),
      groupsToRebuild: {'retry', 'activity'},
    );

    // Simulate API latency
    await Future.delayed(const Duration(milliseconds: 300));

    if (shouldFail) {
      // Emit failure - RetryableUseCaseBuilder will catch this and retry
      emitFailure(
        error: NetworkException(
          'Flaky API failed on attempt $currentAttempt',
          statusCode: 503,
        ),
        errorStackTrace: StackTrace.current,
        groupsToRebuild: {'retry', 'error', 'activity'},
      );
    } else {
      // Success!
      emitUpdate(
        newState: bloc.state.copyWith(
          retryStatus: 'success',
          activityLog: [
            ...bloc.state.activityLog,
            'Flaky API succeeded on attempt $currentAttempt!',
          ],
        ),
        groupsToRebuild: {'retry', 'activity'},
      );
    }
  }
}

/// Use case to reset the retry demo state.
class ResetRetryDemoUseCase
    extends BlocUseCase<FeaturesShowcaseBloc, ResetRetryDemoEvent> {
  @override
  Future<void> execute(ResetRetryDemoEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(
        retryAttempt: 0,
        retryStatus: 'idle',
        activityLog: [
          ...bloc.state.activityLog,
          'Retry demo reset',
        ],
      ),
      groupsToRebuild: {'retry', 'activity'},
    );
  }
}
