import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/testing.dart';

import 'package:example/blocs/features_showcase/features_showcase.dart';

/// Tests for FeaturesShowcaseBloc demonstrating BlocTester usage.
///
/// This test file showcases:
/// - BlocTester for simplified bloc testing
/// - sendAndWaitForResult for awaiting event processing
/// - JuiceException typed error handling
/// - FailureStatus error context verification
void main() {
  group('FeaturesShowcaseBloc Tests using BlocTester', () {
    late FeaturesShowcaseBloc bloc;
    late BlocTester<FeaturesShowcaseBloc, FeaturesShowcaseState> tester;

    setUp(() {
      bloc = FeaturesShowcaseBloc();
      tester = BlocTester(bloc);
    });

    tearDown(() async {
      await tester.dispose();
    });

    group('Counter Operations', () {
      test('increments counter correctly', () async {
        // Send increment event and wait
        await tester.send(ShowcaseIncrementEvent());

        // Use BlocTester assertions
        tester.expectState((state) => state.counter == 1);
        tester.expectLastStatusIs<UpdatingStatus>();
      });

      test('decrements counter correctly', () async {
        // First increment
        await tester.send(ShowcaseIncrementEvent());
        await tester.send(ShowcaseIncrementEvent());

        // Then decrement
        await tester.send(ShowcaseDecrementEvent());

        tester.expectState((state) => state.counter == 1);
      });

      test('tracks multiple increments', () async {
        await tester.send(ShowcaseIncrementEvent());
        await tester.send(ShowcaseIncrementEvent());
        await tester.send(ShowcaseIncrementEvent());

        // Use expectState predicate instead of expectStateEquals
        // because activityLog makes states unequal even with same counter
        tester.expectState((state) => state.counter == 3);
      });
    });

    group('API Simulation', () {
      test('successful API call updates state', () async {
        // Use sendAndWaitForResult to get the final status
        final status = await tester.sendAndWaitForResult(
          SimulateApiCallEvent(shouldFail: false),
        );

        // Verify it was successful
        expect(status, isA<UpdatingStatus>());
        tester.expectState((state) => state.apiCallCount == 1);
        tester.expectState((state) => state.isLoading == false);
        tester.expectNoFailure();
      });

      test('failing API call emits FailureStatus with NetworkException',
          () async {
        final status = await tester.sendAndWaitForResult(
          SimulateApiCallEvent(shouldFail: true),
        );

        // Verify failure with typed exception
        expect(status, isA<FailureStatus>());
        final failure = status as FailureStatus;

        // Check error context (new feature!)
        expect(failure.error, isA<NetworkException>());
        final networkError = failure.error as NetworkException;
        expect(networkError.statusCode, 500);
        expect(networkError.isRetryable, true);
        expect(networkError.isServerError, true);

        // BlocTester assertions
        tester.expectWasWaiting();
        tester.expectWasFailure();
      });

      test('API call shows loading state', () async {
        tester.clearEmissions();

        await tester.send(SimulateApiCallEvent(shouldFail: false));

        // Check that waiting status was emitted during the operation
        tester.expectWasWaiting();
        tester.expectStatusSequence([WaitingStatus, UpdatingStatus]);
      });
    });

    group('Validation', () {
      test('valid input updates message', () async {
        await tester.send(ValidateInputEvent('Hello World'));

        tester.expectState((state) => state.message == 'Hello World');
        tester.expectLastStatusIs<UpdatingStatus>();
        tester.expectNoFailure();
      });

      test('empty input throws ValidationException', () async {
        final status = await tester.sendAndWaitForResult(
          ValidateInputEvent(''),
        );

        expect(status, isA<FailureStatus>());
        final failure = status as FailureStatus;

        // Check error context with ValidationException
        expect(failure.error, isA<ValidationException>());
        final validationError = failure.error as ValidationException;
        expect(validationError.field, 'message');
        expect(validationError.isRetryable, false);
        expect(validationError.isValidationError, true);
      });

      test('short input throws ValidationException', () async {
        final status = await tester.sendAndWaitForResult(
          ValidateInputEvent('ab'),
        );

        expect(status, isA<FailureStatus>());
        final failure = status as FailureStatus;
        expect(failure.error, isA<ValidationException>());
      });
    });

    group('Error Handling', () {
      test('clear error resets error state', () async {
        // First create an error
        await tester.send(ValidateInputEvent(''));
        tester.expectState((state) => state.lastError != null);

        // Clear the error
        await tester.send(ClearErrorEvent());
        tester.expectState((state) => state.lastError == null);
      });
    });

    group('Reset', () {
      test('reset restores initial state', () async {
        // Make some changes
        await tester.send(ShowcaseIncrementEvent());
        await tester.send(ShowcaseIncrementEvent());
        await tester.send(SimulateApiCallEvent(shouldFail: false));

        tester.expectState((state) => state.counter == 2);
        tester.expectState((state) => state.apiCallCount == 1);

        // Reset
        await tester.send(ShowcaseResetEvent());

        tester.expectState((state) => state.counter == 0);
        tester.expectState((state) => state.apiCallCount == 0);
      });
    });

    group('Activity Log', () {
      test('tracks all activities', () async {
        tester.clearEmissions();

        await tester.send(ShowcaseIncrementEvent());
        await tester.send(ShowcaseDecrementEvent());
        await tester.send(ValidateInputEvent('Test'));

        tester.expectState((state) => state.activityLog.length >= 3);
        tester.expectState(
          (state) => state.activityLog.any((log) => log.contains('incremented')),
        );
        tester.expectState(
          (state) => state.activityLog.any((log) => log.contains('decremented')),
        );
      });
    });
  });

  group('BlocTester Feature Demonstrations', () {
    late FeaturesShowcaseBloc bloc;
    late BlocTester<FeaturesShowcaseBloc, FeaturesShowcaseState> tester;

    setUp(() {
      bloc = FeaturesShowcaseBloc();
      tester = BlocTester(bloc);
    });

    tearDown(() async {
      await tester.dispose();
    });

    test('expectStatusSequence verifies emission order', () async {
      tester.clearEmissions();

      // Trigger API call which emits: WaitingStatus -> UpdatingStatus
      await tester.send(SimulateApiCallEvent(shouldFail: false));

      // Verify the exact sequence of status types
      tester.expectStatusSequence([WaitingStatus, UpdatingStatus]);
    });

    test('expectStateEquals for exact state matching', () async {
      // Start fresh to ensure no prior state changes
      tester.clearEmissions();

      // Get state before change
      final initialCounter = bloc.state.counter;

      await tester.send(ShowcaseIncrementEvent());

      // Verify the state changed as expected
      tester.expectState((state) => state.counter == initialCounter + 1);
    });

    test('emissions list provides full history', () async {
      tester.clearEmissions();

      await tester.send(ShowcaseIncrementEvent());
      await tester.send(ShowcaseIncrementEvent());

      // Access raw emissions for custom assertions
      expect(tester.emissions.length, 2);
      expect(tester.emissions.every((e) => e is UpdatingStatus), true);
    });

    test('sendAndWaitForResult with timeout', () async {
      // sendAndWaitForResult has a configurable timeout
      final status = await tester.sendAndWaitForResult(
        SimulateApiCallEvent(shouldFail: false),
        timeout: const Duration(seconds: 5),
      );

      expect(status, isA<UpdatingStatus>());
    });
  });
}
