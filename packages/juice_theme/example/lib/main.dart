import 'package:juice/juice.dart';
import 'package:juice_theme/juice_theme.dart';

/// In-memory persistence so the demo runs with no storage plugin. Swap for
/// `StorageThemePersistence(storageBloc)` in a real app.
class InMemoryThemePersistence implements ThemePersistence {
  ThemeSelection? _saved;
  @override
  Future<ThemeSelection?> load() async => _saved;
  @override
  Future<void> save(ThemeSelection s) async => _saved = s;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  BlocScope.register<ThemeBloc>(
    () => ThemeBloc.withConfig(
      ThemeConfig(persistence: InMemoryThemePersistence()),
    ),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(App());
}

/// The whole MaterialApp rebuilds on theme-mode changes.
class App extends StatelessJuiceWidget<ThemeBloc> {
  App({super.key}) : super(groups: {ThemeGroups.mode});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return MaterialApp(
      title: 'juice_theme demo',
      debugShowCheckedModeBanner: false,
      themeMode: bloc.state.mode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessJuiceWidget<ThemeBloc> {
  HomeScreen({super.key});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Scaffold(
      appBar: AppBar(title: const Text('juice_theme demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Mode: ${bloc.state.mode.name}', key: const Key('mode')),
            const SizedBox(height: 16),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {bloc.state.mode},
              onSelectionChanged: (s) => bloc.setMode(s.first),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: bloc.toggle,
              icon: const Icon(Icons.brightness_6),
              label: const Text('Toggle light/dark'),
            ),
          ],
        ),
      ),
    );
  }
}
