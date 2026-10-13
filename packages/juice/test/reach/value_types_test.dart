import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/testing.dart';
import 'package:matcher/matcher.dart' as m;

/// Small members no other test reached (coverage to 99, 2026-10-07): the
/// entity-status value types, StreamStatus.debugDescription, the three
/// JuiceException subclasses, DeepLinkRoute, BlocLease.isReleased, the
/// default close() of events and builders, JuiceSelectorWith's custom
/// equality, the inline emitter's aviator branches, juiceTest's failure and
/// canceling matchers (and their descriptions), and BlocTester.

class _S extends BlocState {
  const _S(this.n);
  final int n;
  @override
  bool operator ==(Object o) => o is _S && o.n == n;
  @override
  int get hashCode => n;
}

class _Go extends EventBase {
  _Go(this.kind);
  final String kind;
}

class _Fail extends EventBase {}

class _Cancel extends EventBase {}

class _FailUC extends BlocUseCase<_B, _Fail> {
  @override
  Future<void> execute(_Fail e) async =>
      emitFailure(error: StateError('bad'), groupsToRebuild: {'g'});
}

class _CancelUC extends BlocUseCase<_B, _Cancel> {
  @override
  Future<void> execute(_Cancel e) async => emitCancel(groupsToRebuild: {'g'});
}

class _B extends JuiceBloc<_S> {
  _B()
      : super(
          const _S(0),
          [
            () => InlineUseCaseBuilder<_B, _S, _Go>(
                  typeOfEvent: _Go,
                  concurrency: EventConcurrency.sequential,
                  handler: (ctx, e) async {
                    switch (e.kind) {
                      case 'waiting':
                        ctx.emit.waiting(aviatorName: 'home');
                      case 'failure':
                        ctx.emit.failure(aviatorName: 'home');
                      case 'cancel':
                        ctx.emit.cancel(aviatorName: 'home');
                      default:
                        ctx.emit.update(newState: _S(ctx.state.n + 1));
                    }
                  },
                ),
            () => UseCaseBuilder.typed(() => _FailUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _CancelUC(),
                concurrency: EventConcurrency.sequential),
          ],
          [() => Aviator(name: 'home', navigateWhere: (_) => navigated++)],
        );
  static int navigated = 0;
}

/// A minimal UseCaseBuilderBase: inherits the base close.
class _BareBuilder extends UseCaseBuilderBase {
  @override
  Type get eventType => _Fail;
  @override
  EventConcurrency get concurrency => EventConcurrency.concurrent;
  @override
  UseCaseGenerator get generator => () => _FailUC();
  @override
  UseCaseEventBuilder? get initialEventBuilder => null;
}

/// Equal to anything: exercises the non-matcher, non-iterable branch of
/// juiceTest's `expect` wrapping.
class _MatchesAnything {
  @override
  bool operator ==(Object other) => true;
  @override
  int get hashCode => 0;
}

void main() {
  group('EntityStatus value types', () {
    test('EntityFailure equality and hash; EntityStatuses helpers', () {
      // ignore: prefer_const_constructors
      expect(EntityIdle() == EntityIdle(), isTrue,
          reason: 'distinct instances');
      final a = EntityFailure('x');
      final b = EntityFailure('x');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(EntityFailure('y'))));
      var s = EntityStatuses<String>(const {});
      expect(s.isNotEmpty, isFalse);
      expect(s.clear(), same(s), reason: 'clearing empty returns itself');
      s = s.waiting('k');
      expect(s.isNotEmpty, isTrue);
      expect(s.toString(), contains('EntityStatuses'));
      expect(s.clear().isEmpty, isTrue);
    });
  });

  group('FailureStatus.debugDescription', () {
    test('names the failure and its error', () {
      const st = _S(1);
      final f = StreamStatus.failure(st, st, null, error: StateError('e'))
          as FailureStatus<_S>;
      expect(
          f.debugDescription, allOf(startsWith('Failure'), contains('error')));
    });
  });

  group('JuiceException subclasses', () {
    test('construct and carry their message', () {
      // Not const: a const construction is folded at compile time and never
      // executes the constructor body the coverage counts.
      final t =
          JuiceTimeoutException('slow', duration: const Duration(seconds: 1));
      final c = CancelledException('stop');
      final k = ConfigurationException('missing');
      expect(t.message, 'slow');
      expect(t.duration, const Duration(seconds: 1));
      expect(c.message, 'stop');
      expect(k.message, 'missing');
    });
  });

  group('small members', () {
    test('DeepLinkRoute defaults', () {
      final r = DeepLinkRoute(path: const ['a', 'b']);
      expect(r.args, isEmpty);
      expect(r.requiredData, isEmpty);
    });

    test('BlocLease.isReleased flips on release', () {
      BlocScope.register<_B>(() => _B(), lifecycle: BlocLifecycle.leased);
      final lease = BlocScope.lease<_B>();
      expect(lease.isReleased, isFalse);
      lease.dispose();
      expect(lease.isReleased, isTrue);
    });

    test('EventBase.close and UseCaseBuilderBase defaults (close, concurrency)',
        () async {
      await _Fail().close();
      final base = _BareBuilder();
      expect(base.concurrency, EventConcurrency.concurrent);
      await base.close();
    });
  });

  group('inline emitter aviator branches', () {
    test('waiting, failure and cancel each navigate when an aviator is named',
        () async {
      _B.navigated = 0;
      final b = _B();
      await b.send(_Go('waiting'));
      await b.send(_Go('failure'));
      await b.send(_Go('cancel'));
      expect(_B.navigated, 3);
      await b.close();
    });
  });

  group('JuiceSelectorWith', () {
    testWidgets('uses the custom equality', (tester) async {
      final b = _B();
      var builds = 0;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: JuiceSelectorWith<_B, _S, int>(
          bloc: b,
          selector: (s) => s.n,
          equals: (a, c) => (a ~/ 2) == (c ~/ 2), // 0 and 1 are "the same"
          builder: (context, n) {
            builds++;
            return Text('$n', textDirection: TextDirection.ltr);
          },
        ),
      ));
      expect(builds, 1);
      await b.send(_Go('update')); // n = 1: equal under the custom equality
      await tester.pump();
      expect(builds, 1);
      await b.send(_Go('update')); // n = 2: different
      await tester.pump();
      expect(builds, 2);
      await tester.pumpWidget(const SizedBox());
      await b.close();
    });
  });

  group('juiceTest matchers', () {
    test(
        'isFailureStatus and isCancelingStatus match, and describe '
        'themselves on a mismatch', () async {
      await runJuiceTest<_B, _S>(
        build: _B.new,
        act: (b) async {
          await b.send(_Fail());
          await b.send(_Cancel());
        },
        expect: () => [
          isFailureStatus(
              state: const _S(0), groups: {'g'}, error: isA<StateError>()),
          isCancelingStatus(state: const _S(0), groups: {'g'}),
        ],
      );
      final d = m.StringDescription();
      isFailureStatus(
              state: const _S(0), groups: {'g'}, error: isA<StateError>())
          .describe(d);
      expect(
          d.toString(),
          allOf(contains('FailureStatus'), contains('with state'),
              contains('on groups'), contains('with error')));
      final d2 = m.StringDescription();
      isCancelingStatus().describe(d2);
      expect(d2.toString(), 'CancelingStatus');
      // a mismatch on the error
      expect(
          isFailureStatus(error: isA<ArgumentError>()).matches(
              JuiceEmission<_S>(
                  StreamStatus.failure(const _S(0), const _S(0), null,
                      error: StateError('x')),
                  const {}),
              {}),
          isFalse);
    });
  });

  group('juiceTest expect wrapping', () {
    test('a plain value (neither Matcher nor Iterable) is wrapped as-is',
        () async {
      await runJuiceTest<_B, _S>(
        build: _B.new,
        act: (b) => b.send(_Cancel()),
        expect: () => _MatchesAnything(),
      );
    });
  });

  group('BlocTester', () {
    test('expectStateEquals and the canceling status check', () async {
      final b = _B();
      final tester = BlocTester<_B, _S>(b);
      await tester.send(_Cancel());
      tester.expectStateEquals(const _S(0));
      tester.expectStatusSequence([CancelingStatus]);
      // An exact (generic) type falls through to the runtimeType match.
      tester.expectStatusSequence([CancelingStatus<_S>]);
      await b.close();
    });
  });
}
