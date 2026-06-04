import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_i18n/juice_i18n.dart';

class FakeLocalePersistence implements LocalePersistence {
  LocaleChoice? saved;
  FakeLocalePersistence([this.saved]);
  @override
  Future<LocaleChoice?> load() async => saved;
  @override
  Future<void> save(LocaleChoice choice) async => saved = choice;
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  MapTranslationSource source() => MapTranslationSource({
        'en': {
          'greeting': 'Hello {name}',
          'cart.items.one': '{count} item',
          'cart.items.other': '{count} items',
          'cart.items.zero': 'no items',
        },
        'es': {
          'greeting': 'Hola {name}',
          'cart.items.other': '{count} artículos',
        },
      });

  // Fixed system locale so tests don't depend on the host platform.
  I18nConfig cfg({
    LocalePersistence? persistence,
    bool followSystemByDefault = false,
    Locale system = const Locale('en'),
  }) =>
      I18nConfig(
        source: source(),
        fallbackLocale: const Locale('en'),
        persistence: persistence,
        followSystemByDefault: followSystemByDefault,
        resolveSystemLocale: () => system,
      );

  group('initialization', () {
    test('falls back to fallbackLocale when not following system', () async {
      final bloc = I18nBloc.withConfig(cfg());
      await settle();
      expect(bloc.state.locale, const Locale('en'));
      expect(bloc.t('greeting', args: {'name': 'Ada'}), 'Hello Ada');
      await bloc.close();
    });

    test('follows system locale when configured', () async {
      final bloc =
          I18nBloc.withConfig(cfg(followSystemByDefault: true, system: const Locale('es')));
      await settle();
      expect(bloc.state.locale.languageCode, 'es');
      expect(bloc.state.followSystem, isTrue);
      await bloc.close();
    });

    test('restores a persisted choice', () async {
      final p = FakeLocalePersistence(
          const LocaleChoice(locale: Locale('es'), followSystem: false));
      final bloc = I18nBloc.withConfig(cfg(persistence: p));
      await settle();
      expect(bloc.state.locale.languageCode, 'es');
      await bloc.close();
    });
  });

  group('setLocale', () {
    test('switches locale, reloads translations, persists', () async {
      final p = FakeLocalePersistence();
      final bloc = I18nBloc.withConfig(cfg(persistence: p));
      await settle();
      expect(bloc.t('greeting', args: {'name': 'Ada'}), 'Hello Ada');

      bloc.setLocale(const Locale('es'));
      await settle();

      expect(bloc.state.locale.languageCode, 'es');
      expect(bloc.t('greeting', args: {'name': 'Ada'}), 'Hola Ada');
      expect(p.saved?.locale.languageCode, 'es');
      await bloc.close();
    });
  });

  group('resolution', () {
    test('unsupported locale resolves to fallback', () async {
      final bloc = I18nBloc.withConfig(cfg());
      await settle();

      bloc.setLocale(const Locale('fr')); // not supported
      await settle();
      expect(bloc.state.locale, const Locale('en')); // fallback
      await bloc.close();
    });
  });

  group('lookup', () {
    test('missing key returns the key by default', () async {
      final bloc = I18nBloc.withConfig(cfg());
      await settle();
      expect(bloc.t('does.not.exist'), 'does.not.exist');
      await bloc.close();
    });

    test('plural selects one/other/zero and interpolates count', () async {
      final bloc = I18nBloc.withConfig(cfg());
      await settle();
      expect(bloc.plural('cart.items', 0), 'no items');
      expect(bloc.plural('cart.items', 1), '1 item');
      expect(bloc.plural('cart.items', 5), '5 items');
      await bloc.close();
    });

    test('plural falls back to other when a form is absent', () async {
      final bloc = I18nBloc.withConfig(cfg());
      await settle();
      bloc.setLocale(const Locale('es')); // es has only .other
      await settle();
      expect(bloc.plural('cart.items', 1), '1 artículos'); // no .one → .other
      await bloc.close();
    });
  });
}
