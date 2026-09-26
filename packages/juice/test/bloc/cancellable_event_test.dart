import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

class _State extends BlocState {
  final int progress;
  final bool done;
  const _State({this.progress = 0, this.done = false});
  _State copyWith({int? progress, bool? done}) =>
      _State(progress: progress ?? this.progress, done: done ?? this.done);
}

class _WorkEvent extends CancellableEvent {
  final int steps;
  _WorkEvent({this.steps = 5});
}

class _OtherEvent extends CancellableEvent {}

class _TimedEvent extends CancellableEvent with TimeoutSupport {
  _TimedEvent({Duration? timeout}) {
    this.timeout = timeout;
  }
}

/// Cooperatively cancellable loop: checks the flag after every await and
/// emits a CancelingStatus when it observes cancellation.
class _WorkUseCase extends BlocUseCase<_WorkBloc, _WorkEvent> {
  @override
  Future<void> execute(_WorkEvent event) async {
    emitWaiting(groupsToRebuild: {'work'});
    for (var i = 0; i < event.steps; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (event.isCancelled) {
        emitCancel(
          newState: bloc.state.copyWith(progress: i),
          groupsToRebuild: {'work'},
        );
        return;
      }
    }
    emitUpdate(
      newState: bloc.state.copyWith(progress: event.steps, done: true),
      groupsToRebuild: {'work'},
    );
  }
}

class _WorkBloc extends JuiceBloc<_State> {
  _WorkBloc()
      : super(const _State(), [
          () => UseCaseBuilder(
                typeOfEvent: _WorkEvent,
                useCaseGenerator: () => _WorkUseCase(),
              ),
        ]);
}

void main() {
  group('CancellableEvent', () {
    test('starts un-cancelled and cancel() flips the flag', () {
      final e = _WorkEvent();
      expect(e.isCancelled, isFalse);
      e.cancel();
      expect(e.isCancelled, isTrue);
    });

    test('whenCancelled completes on cancel, and cancel is idempotent',
        () async {
      final e = _WorkEvent();
      var completions = 0;
      e.whenCancelled.then((_) => completions++);
      e.cancel();
      e.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(completions, 1);
      expect(e.isCancelled, isTrue);
    });

    test('whenCancelled does not complete while not cancelled', () async {
      final e = _WorkEvent();
      var completed = false;
      e.whenCancelled.then((_) => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(completed, isFalse);
    });

    test('reset() clears the cancelled flag', () {
      final e = _WorkEvent()..cancel();
      // ignore: invalid_use_of_visible_for_testing_member
      e.reset();
      expect(e.isCancelled, isFalse);
    });

    test('equality: identical is equal; different types never equal', () {
      final a = _WorkEvent();
      expect(a == a, isTrue);
      expect(a == _OtherEvent(), isFalse);
      // ignore: unrelated_type_equality_checks
      expect(a == 'not an event', isFalse);
    });

    test('equality is identity; hashCode survives cancel() (1.9.0)', () {
      final a = _WorkEvent();
      final b = _WorkEvent();
      expect(a == b, isFalse, reason: 'two distinct events are not equal');
      final h = a.hashCode;
      final set = {a};
      a.cancel();
      expect(a.hashCode, h);
      expect(set.contains(a), isTrue);
    });
  });

  group('Use case observing cancellation', () {
    late _WorkBloc bloc;
    setUp(() => bloc = _WorkBloc());
    tearDown(() => bloc.close());

    test('sendCancellable returns the same event instance', () async {
      final e = _WorkEvent(steps: 1);
      final returned = bloc.sendCancellable(e);
      expect(identical(returned, e), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bloc.state.done, isTrue);
    });

    test('cancel mid-flight emits CancelingStatus and stops the work',
        () async {
      final statuses = <StreamStatus<_State>>[];
      final sub = bloc.stream.listen(statuses.add);

      final e = bloc.sendCancellable(_WorkEvent(steps: 50));
      await Future<void>.delayed(const Duration(milliseconds: 12));
      e.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();

      expect(statuses.first, isA<WaitingStatus<_State>>());
      expect(statuses.last, isA<CancelingStatus<_State>>());
      expect(identical(statuses.last.event, e), isTrue);
      expect(statuses.last.event!.groupsToRebuild, contains('work'));
      expect(bloc.state.done, isFalse);
      expect(bloc.state.progress, lessThan(50));
      expect(bloc.currentStatus, isA<CancelingStatus<_State>>());
    });

    test('sendCancellable on a closed bloc returns the event without running',
        () async {
      await bloc.close();
      final e = bloc.sendCancellable(_WorkEvent(steps: 1));
      expect(e.isCancelled, isFalse);
      expect(bloc.state.done, isFalse);
    });
  });

  group('TimeoutSupport', () {
    test('no timeout: timeout/timeRemaining null and elapsed zero', () {
      final e = _TimedEvent();
      expect(e.timeout, isNull);
      expect(e.timeRemaining, isNull);
      expect(e.elapsedTime, Duration.zero);
      expect(e.isTimedOut, isFalse);
    });

    test('auto-cancels after the timeout and marks isTimedOut', () async {
      final e = _TimedEvent(timeout: const Duration(milliseconds: 10));
      expect(e.timeout, const Duration(milliseconds: 10));
      expect(e.timeRemaining, isNotNull);
      expect(e.timeRemaining! <= const Duration(milliseconds: 10), isTrue);
      await e.whenCancelled.timeout(const Duration(seconds: 2));
      expect(e.isCancelled, isTrue);
      expect(e.isTimedOut, isTrue);
      expect(e.timeRemaining, Duration.zero);
      expect(e.elapsedTime >= const Duration(milliseconds: 10), isTrue);
    });

    test('manual cancel before timeout is not a timeout and stops the timer',
        () async {
      final e = _TimedEvent(timeout: const Duration(milliseconds: 10));
      e.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(e.isCancelled, isTrue);
      expect(e.isTimedOut, isFalse);
    });

    test('setting timeout to null clears a pending timeout', () async {
      final e = _TimedEvent(timeout: const Duration(milliseconds: 10));
      e.timeout = null;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(e.isCancelled, isFalse);
      expect(e.isTimedOut, isFalse);
      expect(e.timeout, isNull);
    });

    test('re-setting timeout replaces the previous timer', () async {
      final e = _TimedEvent(timeout: const Duration(milliseconds: 10));
      e.timeout = const Duration(seconds: 5);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(e.isCancelled, isFalse);
      e.cancel();
      expect(e.isTimedOut, isFalse);
    });

    test('reset() clears timeout, timing and cancellation state', () async {
      final e = _TimedEvent(timeout: const Duration(milliseconds: 5));
      await e.whenCancelled;
      expect(e.isTimedOut, isTrue);
      // ignore: invalid_use_of_visible_for_testing_member
      e.reset();
      expect(e.isCancelled, isFalse);
      expect(e.isTimedOut, isFalse);
      expect(e.timeout, isNull);
      expect(e.timeRemaining, isNull);
      expect(e.elapsedTime, Duration.zero);
    });

    test('TimeoutSupport equality is identity too (1.9.0)', () async {
      final a = _TimedEvent(timeout: const Duration(seconds: 5));
      final b = _TimedEvent(timeout: const Duration(seconds: 5));
      expect(a == a, isTrue);
      expect(a == b, isFalse);
      final h = a.hashCode;
      a.cancel();
      expect(a.hashCode, h);
    });
  });
}
