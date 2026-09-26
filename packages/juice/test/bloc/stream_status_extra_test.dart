import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

class _S extends BlocState {
  final int v;
  const _S(this.v);

  @override
  bool operator ==(Object other) => other is _S && other.v == v;

  @override
  int get hashCode => v.hashCode;

  @override
  String toString() => '_S($v)';
}

class _Other extends BlocState {
  const _Other();
}

class _E extends EventBase {}

String _whenName(StreamStatus<_S> s) => s.when(
      updating: (st, old, e) => 'updating ${st.v}/${old.v}/${e != null}',
      waiting: (st, old, e) => 'waiting ${st.v}/${old.v}/${e != null}',
      canceling: (st, old, e) => 'canceling ${st.v}/${old.v}/${e != null}',
      failure: (st, old, e) => 'failure ${st.v}/${old.v}/${e != null}',
    );

String _matchName<S extends BlocState>(StreamStatus s,
        {String Function(StreamStatus)? orElse}) =>
    s.match<S, String>(
      updating: (_) => 'u',
      waiting: (_) => 'w',
      canceling: (_) => 'c',
      failure: (_) => 'f',
      orElse: orElse,
    );

void main() {
  const s1 = _S(1);
  const s2 = _S(2);
  const s3 = _S(3);
  final event = _E();

  final all = <StreamStatus<_S>>[
    StreamStatus.updating(s1, s2, event),
    StreamStatus.waiting(s1, s2, event),
    StreamStatus.canceling(s1, s2, event),
    StreamStatus.failure(s1, s2, event, error: 'boom'),
  ];

  group('when dispatches to the callback for the concrete type', () {
    test('each status type routes to its own branch with its fields', () {
      expect(_whenName(all[0]), 'updating 1/2/true');
      expect(_whenName(all[1]), 'waiting 1/2/true');
      expect(_whenName(all[2]), 'canceling 1/2/true');
      expect(_whenName(all[3]), 'failure 1/2/true');
      expect(
          _whenName(StreamStatus.updating(s1, s1, null)), 'updating 1/1/false');
    });
  });

  group('copyWith', () {
    test('preserves the concrete subtype and overrides given fields', () {
      final other = _E();
      for (final s in all) {
        final c = s.copyWith(state: s3, oldState: s1, event: other);
        expect(c.runtimeType, s.runtimeType);
        expect(c.state, s3);
        expect(c.oldState, s1);
        expect(identical(c.event, other), isTrue);
      }
    });

    test('with no arguments yields an equal copy', () {
      for (final s in all) {
        final c = s.copyWith();
        expect(c, equals(s));
        expect(c.hashCode, s.hashCode);
        expect(identical(c, s), isFalse);
      }
    });

    test('FailureStatus.copyWith keeps error and stack trace', () {
      final st = StackTrace.current;
      final f =
          FailureStatus<_S>(s1, s2, event, error: 'e', errorStackTrace: st);
      final c = f.copyWith(state: s3) as FailureStatus<_S>;
      expect(c.error, 'e');
      expect(c.errorStackTrace, st);
      expect(c.state, s3);
    });

    test('FailureStatus.copyWithError overrides or inherits every field', () {
      final st1 = StackTrace.current;
      final st2 = StackTrace.fromString('other');
      final f =
          FailureStatus<_S>(s1, s2, event, error: 'e1', errorStackTrace: st1);

      final inherited = f.copyWithError();
      expect(inherited.error, 'e1');
      expect(inherited.errorStackTrace, st1);
      expect(inherited.state, s1);
      expect(inherited.oldState, s2);
      expect(identical(inherited.event, event), isTrue);

      final other = _E();
      final replaced = f.copyWithError(
        state: s3,
        oldState: s3,
        event: other,
        error: 'e2',
        errorStackTrace: st2,
      );
      expect(replaced.error, 'e2');
      expect(replaced.errorStackTrace, st2);
      expect(replaced.state, s3);
      expect(replaced.oldState, s3);
      expect(identical(replaced.event, other), isTrue);
    });
  });

  group('equality', () {
    test('same type + equal state/oldState/event are equal', () {
      expect(UpdatingStatus<_S>(s1, s2, event),
          equals(UpdatingStatus<_S>(const _S(1), const _S(2), event)));
      expect(UpdatingStatus<_S>(s1, s2, event).hashCode,
          UpdatingStatus<_S>(const _S(1), const _S(2), event).hashCode);
    });

    test('different status types with same payload are not equal', () {
      // all = [updating, waiting, canceling, failure] over the same payload.
      for (var i = 0; i < all.length; i++) {
        for (var j = 0; j < all.length; j++) {
          expect(all[i] == all[j], i == j, reason: '$i vs $j');
        }
      }
    });

    test('differing state, oldState or event breaks equality', () {
      final base = UpdatingStatus<_S>(s1, s2, event);
      expect(base == UpdatingStatus<_S>(s3, s2, event), isFalse);
      expect(base == UpdatingStatus<_S>(s1, s3, event), isFalse);
      expect(base == UpdatingStatus<_S>(s1, s2, _E()), isFalse);
      expect(base == UpdatingStatus<_S>(s1, s2, null), isFalse);
    });

    test('FailureStatus equality includes the error', () {
      final a = FailureStatus<_S>(s1, s2, event, error: 'x');
      final b = FailureStatus<_S>(s1, s2, event, error: 'x');
      final c = FailureStatus<_S>(s1, s2, event, error: 'y');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      final StreamStatus<_S> updating = UpdatingStatus<_S>(s1, s2, event);
      expect(a == updating, isFalse);
    });
  });

  group('FailureStatus.debugDescription', () {
    test('includes state and error when present', () {
      final f = FailureStatus<_S>(s1, s2, event, error: 'kaput');
      expect(f.debugDescription, 'Failure: _S(1) (error: kaput)');
    });

    test('omits error suffix when there is no error', () {
      final f = FailureStatus<_S>(s1, s2, event);
      expect(f.debugDescription, 'Failure: _S(1)');
    });
  });

  group('StatusChecks extension', () {
    test('is*For only matches its own subtype and state type', () {
      final u = all[0], w = all[1], c = all[2], f = all[3];
      expect(u.isUpdatingFor<_S>(), isTrue);
      expect(u.isWaitingFor<_S>(), isFalse);
      expect(w.isWaitingFor<_S>(), isTrue);
      expect(c.isCancelingFor<_S>(), isTrue);
      expect(c.isFailureFor<_S>(), isFalse);
      expect(f.isFailureFor<_S>(), isTrue);
      expect(u.isUpdatingFor<_Other>(), isFalse);
      expect(u.matchesState<_S>(), isTrue);
      expect(u.matchesState<_Other>(), isFalse);
    });

    test('tryCastTo* returns the typed status or null', () {
      final u = all[0], w = all[1], c = all[2], f = all[3];
      expect(u.tryCastToUpdating<_S>(), same(u));
      expect(u.tryCastToWaiting<_S>(), isNull);
      expect(w.tryCastToWaiting<_S>(), same(w));
      expect(w.tryCastToFailure<_S>(), isNull);
      expect(f.tryCastToFailure<_S>(), same(f));
      expect(f.tryCastToFailure<_S>()!.error, 'boom');
      expect(f.tryCastToCanceling<_S>(), isNull);
      expect(c.tryCastToCanceling<_S>(), same(c));
      expect(c.tryCastToUpdating<_S>(), isNull);
      expect(u.tryCastToUpdating<_Other>(), isNull);
    });

    test('match routes each subtype to its callback', () {
      expect(all.map((s) => _matchName<_S>(s)).toList(), ['u', 'w', 'c', 'f']);
    });

    test('match falls back to orElse when state type does not match', () {
      expect(_matchName<_Other>(all[0], orElse: (s) => 'else:${s.runtimeType}'),
          'else:UpdatingStatus<_S>');
    });

    test('match without orElse throws ArgumentError on no match', () {
      expect(() => _matchName<_Other>(all[1]), throwsArgumentError);
    });
  });
}
