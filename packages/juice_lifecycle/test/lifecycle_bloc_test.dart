import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_lifecycle/juice_lifecycle.dart';

/// Pure-Dart fake — drives the bloc without a real WidgetsBinding.
class FakeLifecycleProvider implements LifecycleProvider {
  final _ctrl = StreamController<AppLifecycle>.broadcast();
  AppLifecycle _current;
  bool disposed = false;

  FakeLifecycleProvider([this._current = AppLifecycle.resumed]);

  @override
  Stream<AppLifecycle> get changes => _ctrl.stream;

  @override
  AppLifecycle get current => _current;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _ctrl.close();
  }

  void emit(AppLifecycle p) {
    _current = p;
    _ctrl.add(p);
  }
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('LifecycleState model', () {
    test('foreground / background getters', () {
      expect(const LifecycleState(lifecycle: AppLifecycle.resumed).isForeground,
          isTrue);
      expect(const LifecycleState(lifecycle: AppLifecycle.paused).isBackground,
          isTrue);
      expect(const LifecycleState(lifecycle: AppLifecycle.hidden).isBackground,
          isTrue);
      expect(
          const LifecycleState(lifecycle: AppLifecycle.inactive).isForeground,
          isFalse);
    });

    test('resumedFromBackground only when coming back from non-foreground', () {
      expect(
        const LifecycleState(
                lifecycle: AppLifecycle.resumed, previous: AppLifecycle.paused)
            .resumedFromBackground,
        isTrue,
      );
      expect(
        const LifecycleState(
                lifecycle: AppLifecycle.paused, previous: AppLifecycle.resumed)
            .resumedFromBackground,
        isFalse,
      );
    });
  });

  group('LifecycleBloc', () {
    test('emits the current phase on init', () async {
      final p = FakeLifecycleProvider(AppLifecycle.inactive);
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();

      expect(bloc.state.lifecycle, AppLifecycle.inactive);
      await bloc.close();
    });

    test('tracks transitions and the previous phase', () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();
      expect(bloc.state.isForeground, isTrue);

      p.emit(AppLifecycle.paused);
      await settle();
      expect(bloc.state.isBackground, isTrue);
      expect(bloc.state.previous, AppLifecycle.resumed);

      p.emit(AppLifecycle.resumed);
      await settle();
      expect(bloc.state.isForeground, isTrue);
      expect(bloc.state.previous, AppLifecycle.paused);
      expect(bloc.state.resumedFromBackground, isTrue);
      await bloc.close();
    });

    test('ignores a repeat of the same phase (no-op)', () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();

      p.emit(AppLifecycle.resumed); // same as current
      await settle();
      expect(bloc.state.previous, isNull); // never transitioned
      await bloc.close();
    });

    test('records lastChangedAt on a transition', () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();

      p.emit(AppLifecycle.paused);
      await settle();
      expect(bloc.state.lastChangedAt, isNotNull);
      await bloc.close();
    });

    test('close disposes the provider', () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();

      await bloc.close();
      expect(p.disposed, isTrue);
    });
  });
}
