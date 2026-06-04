import 'package:juice/juice.dart';
import 'package:juice_i18n/juice_i18n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // In-memory source so the demo runs with no assets/storage. Swap for
  // AssetJsonTranslationSource + StorageLocalePersistence in a real app.
  BlocScope.register<I18nBloc>(
    () => I18nBloc.withConfig(I18nConfig(
      followSystemByDefault: false,
      fallbackLocale: const Locale('en'),
      source: MapTranslationSource({
        'en': {
          'title': 'Welcome',
          'greeting': 'Hello {name}',
          'cart.items.one': '{count} item in cart',
          'cart.items.other': '{count} items in cart',
        },
        'es': {
          'title': 'Bienvenido',
          'greeting': 'Hola {name}',
          'cart.items.one': '{count} artículo en el carrito',
          'cart.items.other': '{count} artículos en el carrito',
        },
      }),
    )),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(App());
}

class App extends StatelessJuiceWidget<I18nBloc> {
  App({super.key}) : super(groups: {I18nGroups.locale});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return MaterialApp(
      title: 'juice_i18n demo',
      debugShowCheckedModeBanner: false,
      locale: bloc.state.locale,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessJuiceWidget<I18nBloc> {
  HomeScreen({super.key}) : super(groups: {I18nGroups.translations});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Scaffold(
      appBar: AppBar(title: Text(bloc.t('title'))),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(bloc.t('greeting', args: {'name': 'Ada'}),
                key: const Key('greeting'),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(bloc.plural('cart.items', 3)),
            const SizedBox(height: 24),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'es', label: Text('Español')),
              ],
              selected: {bloc.state.locale.languageCode},
              onSelectionChanged: (s) => bloc.setLocale(Locale(s.first)),
            ),
          ],
        ),
      ),
    );
  }
}
