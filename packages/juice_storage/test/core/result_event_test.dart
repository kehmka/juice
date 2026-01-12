import 'package:flutter_test/flutter_test.dart';
import 'package:juice_storage/src/core/result_event.dart';

class TestResultEvent extends StorageResultEvent<String> {
  TestResultEvent({super.requestId, super.groupsToRebuild});
}

class VoidResultEvent extends StorageResultEvent<void> {
  VoidResultEvent({super.requestId});
}

void main() {
  group('StorageResultEvent', () {
    group('requestId', () {
      test('auto-generates requestId when not provided', () {
        final event1 = TestResultEvent();
        final event2 = TestResultEvent();

        expect(event1.requestId, isNotEmpty);
        expect(event2.requestId, isNotEmpty);
        expect(event1.requestId, isNot(event2.requestId));
      });

      test('uses provided requestId', () {
        final event = TestResultEvent(requestId: 'custom-id');

        expect(event.requestId, 'custom-id');
      });

      test('requestId starts with req_', () {
        final event = TestResultEvent();

        expect(event.requestId, startsWith('req_'));
      });
    });

    group('result', () {
      test('result is a Future', () {
        final event = TestResultEvent();

        expect(event.result, isA<Future<String>>());
      });
    });

    group('isCompleted', () {
      test('returns false before completion', () {
        final event = TestResultEvent();

        expect(event.isCompleted, isFalse);
      });

      test('returns true after succeed', () {
        final event = TestResultEvent();
        event.succeed('success');

        expect(event.isCompleted, isTrue);
      });

      test('returns true after fail', () {
        final event = TestResultEvent();
        event.fail(Exception('error'));

        expect(event.isCompleted, isTrue);
      });
    });

    group('succeed', () {
      test('completes the result with value', () async {
        final event = TestResultEvent();

        event.succeed('hello');

        expect(await event.result, 'hello');
      });

      test('can complete with void', () async {
        final event = VoidResultEvent();

        event.succeed(null);

        // For void results, we just verify it completes without error
        await event.result;
        expect(event.isCompleted, isTrue);
      });

      test('ignores subsequent succeed calls', () async {
        final event = TestResultEvent();

        event.succeed('first');
        event.succeed('second');

        expect(await event.result, 'first');
      });

      test('ignores succeed after fail', () async {
        final event = TestResultEvent();

        event.fail(Exception('error'));
        event.succeed('value');

        expect(event.isCompleted, isTrue);
        expect(event.result, throwsA(isA<Exception>()));
      });
    });

    group('fail', () {
      test('completes the result with error', () async {
        final event = TestResultEvent();

        event.fail(Exception('test error'));

        expect(event.result, throwsA(isA<Exception>()));
      });

      test('includes stack trace', () async {
        final event = TestResultEvent();
        final stackTrace = StackTrace.current;

        event.fail(Exception('error'), stackTrace);

        try {
          await event.result;
          fail('Should have thrown');
        } catch (e, st) {
          expect(e, isA<Exception>());
          expect(st, isNotNull);
        }
      });

      test('ignores subsequent fail calls', () async {
        final event = TestResultEvent();

        event.fail(Exception('first'));
        event.fail(Exception('second'));

        try {
          await event.result;
          fail('Should have thrown');
        } catch (e) {
          expect(e.toString(), contains('first'));
        }
      });

      test('ignores fail after succeed', () async {
        final event = TestResultEvent();

        event.succeed('value');
        event.fail(Exception('error'));

        expect(await event.result, 'value');
      });
    });

    group('groupsToRebuild', () {
      test('passes through groupsToRebuild', () {
        final event = TestResultEvent(
          groupsToRebuild: {'group1', 'group2'},
        );

        expect(event.groupsToRebuild, {'group1', 'group2'});
      });
    });
  });
}
