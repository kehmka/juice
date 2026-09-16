import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_theme/juice_theme.dart';

/// Pure-Dart fake — drives the bloc without real storage.
class FakeThemePersistence implements ThemePersistence {
  ThemeSelection? saved;
  int saveCount = 0;

  FakeThemePersistence([this.saved]);

  @override
  Future<ThemeSelection?> load() async => saved;

  @override
  Future<void> save(ThemeSelection selection) async {
    saved = selection;
    saveCount++;
  }
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('ThemeState model', () {
    test('defaults to system mode, no flavor', () {
      const s = ThemeState();
      expect(s.mode, ThemeMode.system);
      expect(s.flavor, isNull);
      expect(s.isSystemMode, isTrue);
    });

    test('copyWith clearFlavor resets flavor', () {
      const s = ThemeState(mode: ThemeMode.dark, flavor: 'ocean');
      expect(s.copyWith(clearFlavor: true).flavor, isNull);
      expect(s.copyWith(mode: ThemeMode.light).flavor, 'ocean');
    });
  });

  group('ThemeBloc', () {
    test('loads persisted selection on init', () async {
      final p = FakeThemePersistence(
          const ThemeSelection(mode: ThemeMode.dark, flavor: 'ocean'));
      final bloc = ThemeBloc.withConfig(ThemeConfig(persistence: p));
      await settle();

      expect(bloc.state.mode, ThemeMode.dark);
      expect(bloc.state.flavor, 'ocean');
      await bloc.close();
    });

    test('falls back to config defaults when nothing persisted', () async {
      final p = FakeThemePersistence(); // nothing saved
      final bloc = ThemeBloc.withConfig(
        ThemeConfig(persistence: p, defaultMode: ThemeMode.light),
      );
      await settle();

      expect(bloc.state.mode, ThemeMode.light);
      await bloc.close();
    });

    test('setMode updates state and persists', () async {
      final p = FakeThemePersistence();
      final bloc = ThemeBloc.withConfig(ThemeConfig(persistence: p));
      await settle();

      bloc.setMode(ThemeMode.dark);
      await settle();

      expect(bloc.state.mode, ThemeMode.dark);
      expect(p.saved?.mode, ThemeMode.dark);
      await bloc.close();
    });

    test('toggle flips light/dark (system → dark)', () async {
      final p = FakeThemePersistence();
      final bloc = ThemeBloc.withConfig(ThemeConfig(persistence: p));
      await settle(); // starts system

      bloc.toggle();
      await settle();
      expect(bloc.state.mode, ThemeMode.dark); // system → dark

      bloc.toggle();
      await settle();
      expect(bloc.state.mode, ThemeMode.light); // dark → light
      await bloc.close();
    });

    test('setFlavor sets and clears, persisting each time', () async {
      final p = FakeThemePersistence();
      final bloc = ThemeBloc.withConfig(ThemeConfig(persistence: p));
      await settle();

      bloc.setFlavor('ocean');
      await settle();
      expect(bloc.state.flavor, 'ocean');
      expect(p.saved?.flavor, 'ocean');

      bloc.setFlavor(null);
      await settle();
      expect(bloc.state.flavor, isNull);
      expect(p.saved?.flavor, isNull);
      await bloc.close();
    });

    test('in-memory only (null persistence) still works', () async {
      final bloc = ThemeBloc.withConfig(const ThemeConfig());
      await settle();

      bloc.setMode(ThemeMode.dark);
      await settle();
      expect(bloc.state.mode, ThemeMode.dark); // no throw without persistence
      await bloc.close();
    });
  });

  concurrencyModeTests();
}

// ---------------------------------------------------------------------------
// Concurrency modes (0.2.0, ISSUES #22): a gated persistence fake proves the
// mode chosen for each event, the way the rest of the family pins theirs.
// ---------------------------------------------------------------------------

/// load blocks on [loadGate] and counts; each save blocks on its own gate and
/// counts STARTS — so a queued (sequential) save is visible as "not started".
class GatedThemePersistence implements ThemePersistence {
  Completer<void>? loadGate;
  int loads = 0;
  final saveGates = <Completer<void>>[];
  int saveStarts = 0;
  ThemeSelection? saved;

  @override
  Future<ThemeSelection?> load() async {
    loads++;
    if (loadGate != null) await loadGate!.future;
    return saved;
  }

  @override
  Future<void> save(ThemeSelection selection) async {
    saveStarts++;
    final gate = Completer<void>();
    saveGates.add(gate);
    await gate.future;
    saved = selection;
  }
}

void concurrencyModeTests() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('Concurrency modes (0.2.0)', () {
    test('overlapping initializations coalesce to ONE load (droppable)',
        () async {
      final p = GatedThemePersistence()..loadGate = Completer<void>();
      final bloc = ThemeBloc();
      bloc.send(InitializeThemeEvent(config: ThemeConfig(persistence: p)));
      await settle(1); // first init is waiting inside load
      bloc.send(InitializeThemeEvent(config: ThemeConfig(persistence: p)));
      await settle(1);

      expect(p.loads, 1, reason: 'the second init mid-load is dropped');

      p.loadGate!.complete();
      p.loadGate = null;
      await settle();
      expect(bloc.state.mode, ThemeMode.system);
      await bloc.close();
    });

    test('a second mode change does not START its save until the first '
        'completes (sequential) — and persistence ends on the newest', () async {
      final p = GatedThemePersistence();
      final bloc = ThemeBloc.withConfig(ThemeConfig(persistence: p));
      await settle();

      bloc.setMode(ThemeMode.light);
      await settle(1);
      expect(bloc.state.mode, ThemeMode.light,
          reason: 'commit emits synchronously, before the save');
      expect(p.saveStarts, 1);

      bloc.setMode(ThemeMode.dark);
      await settle(1);
      // THE PROPERTY sequential actually has: the dark use case — including
      // its synchronous emit — is queued behind the light one until light's
      // save completes. State does not flip yet.
      expect(bloc.state.mode, ThemeMode.light,
          reason: "sequential queues the whole use case; dark's emit waits "
              "behind light's save");
      expect(p.saveStarts, 1);

      p.saveGates[0].complete(); // light save lands → dark use case runs
      await settle(1);
      expect(bloc.state.mode, ThemeMode.dark, reason: 'dark emits now');
      expect(p.saveStarts, 2, reason: 'and its save starts');
      p.saveGates[1].complete();
      await settle();

      expect(p.saved?.mode, ThemeMode.dark,
          reason: 'persistence holds the newest selection, never an older one');
      await bloc.close();
    });
  });
}
