import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// Pins for `BlocResolver` (BlocScope-backed) and `CompositeResolver`
/// (per-type delegation).

class _S extends BlocState {
  const _S();
}

class _A extends JuiceBloc<_S> {
  _A() : super(const _S(), const []);
}

class _B extends JuiceBloc<_S> {
  _B() : super(const _S(), const []);
}

/// Minimal resolver relying on the interface's default `lease`/`disposeAll`.
class _DefaultsResolver extends BlocDependencyResolver {
  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) =>
      BlocScope.get<T>();
}

class _RecordingResolver implements BlocDependencyResolver {
  _RecordingResolver(this.bloc);
  final JuiceBloc bloc;
  final calls = <String>[];

  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) {
    calls.add('resolve:$T');
    return bloc as T;
  }

  @override
  BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) {
    calls.add('lease:$T:$scope');
    return BlocScope.lease<T>(scope: scope);
  }

  @override
  Future<void> disposeAll() async => calls.add('disposeAll');
}

void main() {
  setUp(BlocScope.reset);
  tearDown(BlocScope.reset);

  group('BlocResolver', () {
    test('resolve returns the BlocScope singleton', () {
      BlocScope.register<_A>(() => _A());
      final r = BlocResolver();
      final a = r.resolve<_A>();
      expect(identical(a, BlocScope.get<_A>()), isTrue);
      expect(identical(r.resolve<_A>(), a), isTrue);
    });

    test('resolve of an unregistered bloc throws', () {
      expect(() => BlocResolver().resolve<_A>(), throwsStateError);
    });

    test('lease honours scope and releasing the last lease closes', () async {
      BlocScope.register<_A>(() => _A(),
          lifecycle: BlocLifecycle.leased, scope: 'k');
      final lease = BlocResolver().lease<_A>(scope: 'k');
      final bloc = lease.bloc;
      expect(bloc.isClosed, isFalse);
      lease.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.isClosed, isTrue);
    });

    test('disposeAll ends every live bloc', () async {
      BlocScope.register<_A>(() => _A());
      BlocScope.register<_B>(() => _B());
      final a = BlocScope.get<_A>();
      final b = BlocScope.get<_B>();
      await BlocResolver().disposeAll();
      expect(a.isClosed, isTrue);
      expect(b.isClosed, isTrue);
    });
  });

  group('BlocDependencyResolver defaults', () {
    test('default lease goes through BlocScope; disposeAll is a no-op',
        () async {
      BlocScope.register<_A>(() => _A());
      final r = _DefaultsResolver();
      final lease = r.lease<_A>();
      expect(identical(lease.bloc, BlocScope.get<_A>()), isTrue);
      lease.dispose();
      await r.disposeAll();
      expect(BlocScope.get<_A>().isClosed, isFalse);
    });
  });

  group('CompositeResolver', () {
    test('resolve delegates by exact type', () {
      final a = _A();
      final b = _B();
      final ra = _RecordingResolver(a);
      final rb = _RecordingResolver(b);
      final c = CompositeResolver({_A: ra, _B: rb});
      expect(identical(c.resolve<_A>(), a), isTrue);
      expect(identical(c.resolve<_B>(), b), isTrue);
      expect(ra.calls, ['resolve:_A']);
      expect(rb.calls, ['resolve:_B']);
    });

    test('resolve for an unmapped type throws naming the type', () {
      final c = CompositeResolver({});
      expect(
          () => c.resolve<_A>(),
          throwsA(isA<Exception>().having((e) => e.toString(), 'message',
              contains('No resolver found for _A'))));
    });

    test('lease delegates when mapped, else falls back to BlocScope', () {
      BlocScope.register<_A>(() => _A());
      BlocScope.register<_B>(() => _B(), scope: 's');
      final ra = _RecordingResolver(_A());
      final c = CompositeResolver({_A: ra});

      final la = c.lease<_A>();
      expect(ra.calls, ['lease:_A:null']);
      expect(identical(la.bloc, BlocScope.get<_A>()), isTrue);

      final lb = c.lease<_B>(scope: 's');
      expect(identical(lb.bloc, BlocScope.get<_B>(scope: 's')), isTrue);
      expect(ra.calls, hasLength(1));
      la.dispose();
      lb.dispose();
    });

    test('disposeAll awaits every delegate', () async {
      final ra = _RecordingResolver(_A());
      final rb = _RecordingResolver(_B());
      await CompositeResolver({_A: ra, _B: rb}).disposeAll();
      expect(ra.calls, ['disposeAll']);
      expect(rb.calls, ['disposeAll']);
    });
  });
}
