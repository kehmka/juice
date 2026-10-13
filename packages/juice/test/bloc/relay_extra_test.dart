// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

class _Src extends BlocState {
  final int count;
  const _Src([this.count = 0]);
}

class _Dst extends BlocState {
  final List<String> labels;
  const _Dst([this.labels = const []]);
}

class _Bump extends EventBase {}

class _Record extends EventBase {
  final String label;
  _Record(this.label);
}

class _SrcBloc extends JuiceBloc<_Src> {
  _SrcBloc()
      : super(const _Src(), [
          () => InlineUseCaseBuilder<_SrcBloc, _Src, _Bump>(
                typeOfEvent: _Bump,
                handler: (ctx, e) async {
                  ctx.emit.waiting();
                  ctx.emit.update(newState: _Src(ctx.state.count + 1));
                },
                concurrency: EventConcurrency.concurrent,
              ),
        ]);
}

class _DstBloc extends JuiceBloc<_Dst> {
  _DstBloc()
      : super(const _Dst(), [
          () => InlineUseCaseBuilder<_DstBloc, _Dst, _Record>(
                typeOfEvent: _Record,
                handler: (ctx, e) async => ctx.emit
                    .update(newState: _Dst([...ctx.state.labels, e.label])),
                concurrency: EventConcurrency.concurrent,
              ),
        ]);
}

class _MapResolver implements BlocDependencyResolver {
  final Map<Type, JuiceBloc> blocs;
  _MapResolver(this.blocs);

  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) =>
      blocs[T] as T;

  @override
  BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) =>
      throw UnimplementedError();

  @override
  Future<void> disposeAll() async {}
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  setUp(BlocScope.reset);
  tearDown(BlocScope.reset);

  void registerBoth({Object? srcScope, Object? dstScope}) {
    BlocScope.register<_SrcBloc>(() => _SrcBloc(), scope: srcScope);
    BlocScope.register<_DstBloc>(() => _DstBloc(), scope: dstScope);
  }

  group('StateRelay via BlocScope', () {
    test('leases both blocs, relays state, and releases leases on close',
        () async {
      registerBoth();
      final relay = StateRelay<_SrcBloc, _DstBloc, _Src>(
        toEvent: (s) => _Record('state:${s.count}'),
        when: (s) => s.count > 0,
      );
      await _settle();
      expect(BlocScope.diagnostics<_SrcBloc>()!.leaseCount, 1);
      expect(BlocScope.diagnostics<_DstBloc>()!.leaseCount, 1);

      await BlocScope.get<_SrcBloc>().send(_Bump());
      await _settle();
      // Waiting (count 0) is filtered by `when`; the update (count 1) relays.
      expect(BlocScope.get<_DstBloc>().state.labels, ['state:1']);

      await relay.close();
      expect(relay.isClosed, isTrue);
      expect(BlocScope.diagnostics<_SrcBloc>()!.leaseCount, 0);
      expect(BlocScope.diagnostics<_DstBloc>()!.leaseCount, 0);
    });

    test('init failure (unregistered bloc) THROWS at construction (2.0.0)', () {
      expect(
          () => StateRelay<_SrcBloc, _DstBloc, _Src>(
              toEvent: (s) => _Record('x')),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('not registered'))));
    });

    test('init failure with a closed bloc THROWS at construction', () async {
      final src = _SrcBloc();
      final dst = _DstBloc();
      await src.close();
      expect(
          () => StateRelay<_SrcBloc, _DstBloc, _Src>(
                toEvent: (s) => _Record('x'),
                resolver: _MapResolver({_SrcBloc: src, _DstBloc: dst}),
              ),
          throwsA(isA<StateError>().having(
              (e) => e.toString(), 'message', contains('closed blocs'))));
      await dst.close();
    });
  });

  group('StatusRelay', () {
    test('relays every status via scoped BlocScope leases', () async {
      registerBoth(srcScope: 's', dstScope: 'd');
      final relay = StatusRelay<_SrcBloc, _DstBloc, _Src>(
        sourceScope: 's',
        destScope: 'd',
        toEvent: (status) => _Record(status.when(
          updating: (s, _, __) => 'u${s.count}',
          waiting: (s, _, __) => 'w${s.count}',
          canceling: (s, _, __) => 'c',
          failure: (s, _, __) => 'f',
        )),
      );
      await _settle();
      expect(BlocScope.diagnostics<_SrcBloc>(scope: 's')!.leaseCount, 1);

      await BlocScope.get<_SrcBloc>(scope: 's').send(_Bump());
      await _settle();
      expect(BlocScope.get<_DstBloc>(scope: 'd').state.labels, ['w0', 'u1']);

      await relay.close();
      await relay.close(); // idempotent
      expect(BlocScope.diagnostics<_DstBloc>(scope: 'd')!.leaseCount, 0);
    });

    test('closes itself when the destination bloc is closed', () async {
      final src = _SrcBloc();
      final dst = _DstBloc();
      final relay = StatusRelay<_SrcBloc, _DstBloc, _Src>(
        toEvent: (s) => _Record('x'),
        resolver: _MapResolver({_SrcBloc: src, _DstBloc: dst}),
      );
      await _settle();
      await dst.close();
      expect(relay.isClosed, isFalse);
      await src.send(_Bump());
      await _settle();
      expect(relay.isClosed, isTrue);
      await src.close();
    });

    test('transformer errors are logged and the relay keeps running', () async {
      final src = _SrcBloc();
      final dst = _DstBloc();
      final relay = StatusRelay<_SrcBloc, _DstBloc, _Src>(
        toEvent: (status) {
          if (status is WaitingStatus) throw StateError('no waiting');
          return _Record('u${status.state.count}');
        },
        resolver: _MapResolver({_SrcBloc: src, _DstBloc: dst}),
      );
      await _settle();
      await src.send(_Bump());
      await src.send(_Bump());
      await _settle();
      expect(relay.isClosed, isFalse);
      expect(dst.state.labels, ['u1', 'u2']);
      await relay.close();
      await src.close();
      await dst.close();
    });

    test('init failures THROW at construction (2.0.0)', () async {
      expect(
          () => StatusRelay<_SrcBloc, _DstBloc, _Src>(
              toEvent: (s) => _Record('x')),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('not registered'))));

      final src = _SrcBloc();
      final dst = _DstBloc();
      await dst.close();
      expect(
          () => StatusRelay<_SrcBloc, _DstBloc, _Src>(
                toEvent: (s) => _Record('x'),
                resolver: _MapResolver({_SrcBloc: src, _DstBloc: dst}),
              ),
          throwsA(isA<StateError>().having(
              (e) => e.toString(), 'message', contains('closed blocs'))));
      await src.close();
    });
  });
}
