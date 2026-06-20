// ignore_for_file: must_be_immutable

import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

void main() {
  group('EntityStatus.when', () {
    test('dispatches each variant', () {
      String tag(EntityStatus s) => s.when(
            idle: () => 'idle',
            waiting: () => 'waiting',
            failure: (e) => 'failure:$e',
          );
      expect(tag(const EntityIdle()), 'idle');
      expect(tag(const EntityWaiting()), 'waiting');
      expect(tag(const EntityFailure('boom')), 'failure:boom');
    });

    test('maybeWhen falls back to orElse', () {
      expect(const EntityIdle().maybeWhen(orElse: () => 'x'), 'x');
      expect(
        const EntityWaiting().maybeWhen(waiting: () => 'w', orElse: () => 'x'),
        'w',
      );
    });

    test('predicates', () {
      expect(const EntityIdle().isIdle, isTrue);
      expect(const EntityWaiting().isWaiting, isTrue);
      expect(const EntityFailure('e').isFailure, isTrue);
    });
  });

  group('EntityStatuses', () {
    test('unknown key reads as idle; map starts empty', () {
      const s = EntityStatuses<String>();
      expect(s.statusOf('a'), const EntityIdle());
      expect(s.isEmpty, isTrue);
      expect(s.anyWaiting, isFalse);
    });

    test('waiting / failure / idle transitions are immutable', () {
      const s0 = EntityStatuses<String>();
      final s1 = s0.waiting('a');
      expect(s0.isWaiting('a'), isFalse, reason: 'original untouched');
      expect(s1.isWaiting('a'), isTrue);
      expect(s1.anyWaiting, isTrue);
      expect(s1.waitingKeys, ['a']);

      final s2 = s1.failure('a', 'nope');
      expect(s2.isWaiting('a'), isFalse);
      expect(s2.isFailure('a'), isTrue);
      expect(s2.statusOf('a'), const EntityFailure('nope'));
      expect(s2.failedKeys, ['a']);

      final s3 = s2.idle('a');
      expect(s3.statusOf('a'), const EntityIdle());
      expect(s3.isEmpty, isTrue, reason: 'idle removes the entry');
    });

    test('independent keys do not interfere', () {
      final s = const EntityStatuses<String>().waiting('a').failure('b', 'x');
      expect(s.isWaiting('a'), isTrue);
      expect(s.isFailure('b'), isTrue);
      expect(s.statusOf('c'), const EntityIdle());
      expect(s.length, 2);
    });

    test('value equality (so state diffing works)', () {
      final a = const EntityStatuses<String>().waiting('x');
      final b = const EntityStatuses<String>().waiting('x');
      final c = const EntityStatuses<String>().waiting('y');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('idle on absent key is a no-op (same instance)', () {
      const s = EntityStatuses<String>();
      expect(identical(s.idle('missing'), s), isTrue);
    });
  });

  group('BlocUseCase.guardEntity', () {
    setUp(() => BlocScope.reset());
    tearDown(() => BlocScope.reset());

    test('sets waiting during the action, then clears to idle on success',
        () async {
      final bloc = _GuardBloc();
      final gate = Completer<void>();

      bloc.send(_GuardEvent('a', action: () => gate.future));
      await Future<void>.delayed(Duration.zero); // let the use case start

      expect(bloc.state.statuses.isWaiting('a'), isTrue,
          reason: 'waiting while the action is in flight');

      gate.complete();
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.statuses.isWaiting('a'), isFalse);
      expect(bloc.state.statuses.isEmpty, isTrue,
          reason: 'idle clears the entry');
      await bloc.close();
    });

    test('records failure (with error) when the action throws', () async {
      final bloc = _GuardBloc();

      bloc.send(_GuardEvent('b',
          action: () => Future<void>.error(StateError('kaboom'))));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.statuses.isFailure('b'), isTrue);
      final status = bloc.state.statuses.statusOf('b');
      expect(status, isA<EntityFailure>());
      expect((status as EntityFailure).error, isA<StateError>());
      await bloc.close();
    });
  });
}

// --- self-contained harness for guardEntity ---

class _GuardState extends BlocState {
  final EntityStatuses<String> statuses;
  _GuardState({this.statuses = const EntityStatuses<String>()});
  _GuardState copyWith({EntityStatuses<String>? statuses}) =>
      _GuardState(statuses: statuses ?? this.statuses);
}

class _GuardEvent extends EventBase {
  final String key;
  final Future<void> Function() action;
  _GuardEvent(this.key, {required this.action});
}

class _GuardUseCase extends BlocUseCase<_GuardBloc, _GuardEvent> {
  @override
  Future<void> execute(_GuardEvent event) => guardEntity<String, void>(
        event.key,
        read: (b) => b.state.statuses,
        write: (s) => bloc.state.copyWith(statuses: s),
        groupsToRebuild: {'guard'},
        action: event.action,
      );
}

class _GuardBloc extends JuiceBloc<_GuardState> {
  _GuardBloc()
      : super(
          _GuardState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: _GuardEvent,
                  useCaseGenerator: () => _GuardUseCase(),
                ),
          ],
          [],
        );
}
