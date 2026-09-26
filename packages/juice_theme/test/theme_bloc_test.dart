import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice/testing.dart';
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

  // Ported to juiceTest (juice 1.9.0): no settle() sleeps — each act awaits
  // the processing of the events it sends — and every emission's rebuild
  // groups are asserted, which the settle()-based versions never checked.
  group('ThemeBloc', () {
    Matcher theme({ThemeMode? mode, Object? flavor = _any}) => isA<ThemeState>()
        .having((s) => s.mode, 'mode', mode ?? anything)
        .having((s) => s.flavor, 'flavor',
            identical(flavor, _any) ? anything : flavor);

    Future<void> init(ThemeBloc b, ThemeConfig config) =>
        b.send(InitializeThemeEvent(config: config));

    final darkOcean = FakeThemePersistence(
        const ThemeSelection(mode: ThemeMode.dark, flavor: 'ocean'));
    juiceTest<ThemeBloc, ThemeState>(
      'loads persisted selection on init, on every theme group',
      build: () => ThemeBloc(),
      act: (b) => init(b, ThemeConfig(persistence: darkOcean)),
      expect: () => [
        isUpdatingStatus(
          state: theme(mode: ThemeMode.dark, flavor: 'ocean'),
          groups: ThemeGroups.all,
        ),
      ],
    );

    juiceTest<ThemeBloc, ThemeState>(
      'falls back to config defaults when nothing persisted',
      build: () => ThemeBloc(),
      act: (b) => init(
        b,
        ThemeConfig(
            persistence: FakeThemePersistence(), defaultMode: ThemeMode.light),
      ),
      expect: () => [isUpdatingStatus(state: theme(mode: ThemeMode.light))],
    );

    final setModeStore = FakeThemePersistence();
    juiceTest<ThemeBloc, ThemeState>(
      'setMode updates state on the mode group only, and persists',
      build: () => ThemeBloc(),
      act: (b) async {
        await init(b, ThemeConfig(persistence: setModeStore));
        await b.send(SetThemeModeEvent(ThemeMode.dark));
      },
      skip: 1, // the init emission
      expect: () => [
        isUpdatingStatus(
          state: theme(mode: ThemeMode.dark),
          groups: {ThemeGroups.mode},
        ),
      ],
      verify: (_) => expect(setModeStore.saved?.mode, ThemeMode.dark),
    );

    juiceTest<ThemeBloc, ThemeState>(
      'toggle flips light/dark (system → dark → light)',
      build: () => ThemeBloc(),
      act: (b) async {
        await init(b, ThemeConfig(persistence: FakeThemePersistence()));
        await b.send(ToggleThemeEvent());
        await b.send(ToggleThemeEvent());
      },
      skip: 1,
      expect: () => [
        isUpdatingStatus(
            state: theme(mode: ThemeMode.dark), groups: {ThemeGroups.mode}),
        isUpdatingStatus(
            state: theme(mode: ThemeMode.light), groups: {ThemeGroups.mode}),
      ],
    );

    final flavorStore = FakeThemePersistence();
    juiceTest<ThemeBloc, ThemeState>(
      'setFlavor sets and clears on the flavor group, persisting each time',
      build: () => ThemeBloc(),
      act: (b) async {
        await init(b, ThemeConfig(persistence: flavorStore));
        await b.send(SetFlavorEvent('ocean'));
        expect(flavorStore.saved?.flavor, 'ocean');
        await b.send(SetFlavorEvent(null));
      },
      skip: 1,
      expect: () => [
        isUpdatingStatus(
            state: theme(flavor: 'ocean'), groups: {ThemeGroups.flavor}),
        isUpdatingStatus(
            state: theme(flavor: null), groups: {ThemeGroups.flavor}),
      ],
      verify: (_) {
        expect(flavorStore.saved?.flavor, isNull);
        expect(flavorStore.saveCount, 2);
      },
    );

    juiceTest<ThemeBloc, ThemeState>(
      'in-memory only (null persistence) still works',
      build: () => ThemeBloc(),
      act: (b) async {
        await init(b, const ThemeConfig());
        await b.send(SetThemeModeEvent(ThemeMode.dark));
      },
      skip: 1,
      expect: () => [isUpdatingStatus(state: theme(mode: ThemeMode.dark))],
    );
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

    test(
        'a second mode change does not START its save until the first '
        'completes (sequential) — and persistence ends on the newest',
        () async {
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

const Object _any = Object();
