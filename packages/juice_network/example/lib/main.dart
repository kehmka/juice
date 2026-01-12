import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import 'package:juice_storage/juice_storage.dart';

import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register StorageBloc as permanent
  if (!BlocScope.isRegistered<StorageBloc>()) {
    BlocScope.register<StorageBloc>(
      () => StorageBloc(
        config: const StorageConfig(
          prefsKeyPrefix: 'fetch_arcade_',
          hiveBoxesToOpen: ['_fetch_cache'],
        ),
      ),
      lifecycle: BlocLifecycle.permanent,
    );
  }

  // Initialize storage
  final storageBloc = BlocScope.get<StorageBloc>();
  await storageBloc.initialize();

  // Register FetchBloc as permanent
  if (!BlocScope.isRegistered<FetchBloc>()) {
    BlocScope.register<FetchBloc>(
      () => FetchBloc(storageBloc: storageBloc),
      lifecycle: BlocLifecycle.permanent,
    );
  }

  // Initialize FetchBloc with JSONPlaceholder config
  final fetchBloc = BlocScope.get<FetchBloc>();
  await fetchBloc.send(InitializeFetchEvent(
    config: FetchConfig(
      baseUrl: 'https://jsonplaceholder.typicode.com',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      defaultTtl: const Duration(minutes: 5),
    ),
  ));

  runApp(const FetchArcadeApp());
}

class FetchArcadeApp extends StatelessWidget {
  const FetchArcadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fetch Arcade',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
