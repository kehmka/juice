import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

void main() {
  group('CleanupBarrierResult', () {
    test('allSucceeded is true when completed with no failures', () {
      const result = CleanupBarrierResult(
        completed: true,
        timedOut: false,
        failedCount: 0,
        taskCount: 2,
      );

      expect(result.allSucceeded, isTrue);
    });

    test('allSucceeded is false when timed out', () {
      const result = CleanupBarrierResult(
        completed: false,
        timedOut: true,
        failedCount: 0,
        taskCount: 2,
      );

      expect(result.allSucceeded, isFalse);
    });

    test('allSucceeded is false when there are failures', () {
      const result = CleanupBarrierResult(
        completed: true,
        timedOut: false,
        failedCount: 1,
        taskCount: 2,
      );

      expect(result.allSucceeded, isFalse);
    });
  });

  group('CleanupBarrier', () {
    test('add returns true before wait is called', () {
      final barrier = CleanupBarrier();

      final added = barrier.add(Future.value());

      expect(added, isTrue);
      expect(barrier.pendingCount, 1);
    });

    test('add returns false after wait is called', () async {
      final barrier = CleanupBarrier();
      barrier.add(Future.value());

      await barrier.wait();
      final added = barrier.add(Future.value());

      expect(added, isFalse);
      expect(barrier.isClosed, isTrue);
    });

    test('wait with empty barrier returns immediately', () async {
      final barrier = CleanupBarrier();

      final result = await barrier.wait();

      expect(result.completed, isTrue);
      expect(result.timedOut, isFalse);
      expect(result.failedCount, 0);
      expect(result.taskCount, 0);
    });

    test('wait completes all tasks', () async {
      final barrier = CleanupBarrier();
      var task1Done = false;
      var task2Done = false;

      barrier.add(Future.delayed(Duration(milliseconds: 10), () {
        task1Done = true;
      }));
      barrier.add(Future.delayed(Duration(milliseconds: 20), () {
        task2Done = true;
      }));

      final result = await barrier.wait();

      expect(result.completed, isTrue);
      expect(result.timedOut, isFalse);
      expect(result.taskCount, 2);
      expect(task1Done, isTrue);
      expect(task2Done, isTrue);
    });

    test('wait times out on slow tasks', () async {
      final barrier = CleanupBarrier();

      barrier.add(Future.delayed(Duration(seconds: 5)));

      final result = await barrier.wait(timeout: Duration(milliseconds: 50));

      expect(result.completed, isFalse);
      expect(result.timedOut, isTrue);
      expect(result.taskCount, 1);
    });

    test('wait catches task errors and counts them', () async {
      final barrier = CleanupBarrier();

      barrier.add(Future.value());
      barrier.add(Future.error('error 1'));
      barrier.add(Future.error('error 2'));

      final result = await barrier.wait();

      expect(result.completed, isTrue);
      expect(result.failedCount, 2);
      expect(result.taskCount, 3);
    });

    test('wait does not throw on task errors', () async {
      final barrier = CleanupBarrier();
      barrier.add(Future.error('error'));

      // This should not throw
      final result = await barrier.wait();

      expect(result.failedCount, 1);
    });

    test('isClosed is true after wait', () async {
      final barrier = CleanupBarrier();

      expect(barrier.isClosed, isFalse);
      await barrier.wait();
      expect(barrier.isClosed, isTrue);
    });

    test('pendingCount tracks added tasks', () {
      final barrier = CleanupBarrier();

      expect(barrier.pendingCount, 0);
      barrier.add(Future.value());
      expect(barrier.pendingCount, 1);
      barrier.add(Future.value());
      expect(barrier.pendingCount, 2);
    });
  });
}
