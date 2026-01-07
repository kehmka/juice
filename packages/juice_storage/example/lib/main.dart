import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';

import 'screens/arcade_screen.dart';
import 'screens/inspector_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register StorageBloc as a permanent bloc
  if (!BlocScope.isRegistered<StorageBloc>()) {
    BlocScope.register<StorageBloc>(
      () => StorageBloc(
        config: const StorageConfig(
          prefsKeyPrefix: 'arcade_',
          hiveBoxesToOpen: ['arcade_box'],
          sqliteDatabaseName: 'arcade.db',
          enableBackgroundCleanup: false, // We'll trigger manually in demo
        ),
      ),
      lifecycle: BlocLifecycle.permanent,
    );
  }

  // Initialize storage before running app
  final storage = BlocScope.get<StorageBloc>();
  await storage.initialize();

  runApp(const StorageArcadeApp());
}

class StorageArcadeApp extends StatelessWidget {
  const StorageArcadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Storage Arcade',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const ArcadeScreen(),
      const InspectorScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Arcade',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Inspector',
          ),
        ],
      ),
    );
  }
}
