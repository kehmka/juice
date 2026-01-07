import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_storage/src/core/operation_result.dart';

class TestState extends BlocState {
  final int value;
  const TestState({this.value = 0});
}

class TestEvent extends EventBase {
  TestEvent();
}

void main() {
  group('OperationResult', () {
    late TestEvent testEvent;

    setUp(() {
      testEvent = TestEvent();
    });

    group('isSuccess', () {
      test('returns true for UpdatingStatus', () {
        final status = UpdatingStatus<TestState>(
          const TestState(value: 42),
          const TestState(),
          testEvent,
        );
        final result = OperationResult<String, TestState>(
          status: status,
          value: 'success',
        );

        expect(result.isSuccess, isTrue);
        expect(result.isFailure, isFalse);
      });
    });

    group('isFailure', () {
      test('returns true for FailureStatus', () {
        final status = FailureStatus<TestState>(
          const TestState(),
          const TestState(),
          testEvent,
          error: Exception('error'),
        );
        final result = OperationResult<String, TestState>(
          status: status,
          value: null,
        );

        expect(result.isFailure, isTrue);
        expect(result.isSuccess, isFalse);
      });
    });

    group('value', () {
      test('returns the value', () {
        final status = UpdatingStatus<TestState>(
          const TestState(),
          const TestState(),
          testEvent,
        );
        final result = OperationResult<String, TestState>(
          status: status,
          value: 'hello',
        );

        expect(result.value, 'hello');
      });

      test('can be null', () {
        final status = UpdatingStatus<TestState>(
          const TestState(),
          const TestState(),
          testEvent,
        );
        final result = OperationResult<String?, TestState>(
          status: status,
          value: null,
        );

        expect(result.value, isNull);
      });
    });

    group('status', () {
      test('returns the status', () {
        final status = UpdatingStatus<TestState>(
          const TestState(value: 99),
          const TestState(),
          testEvent,
        );
        final result = OperationResult<String, TestState>(
          status: status,
          value: 'value',
        );

        expect(result.status, status);
        expect(result.status.state.value, 99);
      });
    });

    group('error', () {
      test('returns error from failure status', () {
        final error = Exception('test error');
        final status = FailureStatus<TestState>(
          const TestState(),
          const TestState(),
          testEvent,
          error: error,
        );
        final result = OperationResult<String, TestState>(
          status: status,
          value: null,
        );

        expect(result.error, error);
      });

      test('returns null for non-failure status', () {
        final status = UpdatingStatus<TestState>(
          const TestState(),
          const TestState(),
          testEvent,
        );
        final result = OperationResult<String, TestState>(
          status: status,
          value: 'value',
        );

        expect(result.error, isNull);
      });
    });

    group('errorStackTrace', () {
      test('returns stack trace from failure status', () {
        final stackTrace = StackTrace.current;
        final status = FailureStatus<TestState>(
          const TestState(),
          const TestState(),
          testEvent,
          error: Exception('error'),
          errorStackTrace: stackTrace,
        );
        final result = OperationResult<String, TestState>(
          status: status,
          value: null,
        );

        expect(result.errorStackTrace, stackTrace);
      });
    });

    group('failure getter', () {
      test('returns FailureStatus when isFailure', () {
        final status = FailureStatus<TestState>(
          const TestState(),
          const TestState(),
          testEvent,
          error: Exception('error'),
        );
        final result = OperationResult<String, TestState>(
          status: status,
          value: null,
        );

        expect(result.failure, status);
      });

      test('returns null when not failure', () {
        final status = UpdatingStatus<TestState>(
          const TestState(),
          const TestState(),
          testEvent,
        );
        final result = OperationResult<String, TestState>(
          status: status,
          value: 'value',
        );

        expect(result.failure, isNull);
      });
    });

    group('isCanceled', () {
      test('returns true for CancelingStatus', () {
        final status = CancelingStatus<TestState>(
          const TestState(),
          const TestState(),
          testEvent,
        );
        final result = OperationResult<String, TestState>(
          status: status,
          value: null,
        );

        expect(result.isCanceled, isTrue);
        expect(result.isSuccess, isFalse);
        expect(result.isFailure, isFalse);
      });
    });
  });
}
