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
}
