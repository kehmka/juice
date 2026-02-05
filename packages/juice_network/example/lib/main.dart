import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import 'package:juice_storage/juice_storage.dart';

import 'blocs/blocs.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register StorageBloc as permanent (app-wide service)
  if (!BlocScope.isRegistered<StorageBloc>()) {
    BlocScope.register<StorageBloc>(
      () => StorageBloc(
        config: StorageConfig(
          prefsKeyPrefix: 'fetch_arcade_',
          hiveBoxesToOpen: [CacheManager.cacheBoxName],
        ),
      ),
      lifecycle: BlocLifecycle.permanent,
    );
  }

  // Initialize storage
  final storageBloc = BlocScope.get<StorageBloc>();
  await storageBloc.initialize();

  // Register FetchBloc as permanent (app-wide service)
  if (!BlocScope.isRegistered<FetchBloc>()) {
    BlocScope.register<FetchBloc>(
      () => FetchBloc(storageBloc: storageBloc),
      lifecycle: BlocLifecycle.permanent,
    );
  }

  // Initialize FetchBloc with DummyJSON config
  // Note: jsonplaceholder.typicode.com is blocked by Cloudflare for Dart clients
  final fetchBloc = BlocScope.get<FetchBloc>();
  await fetchBloc.send(InitializeFetchEvent(
    config: FetchConfig(
      baseUrl: 'https://dummyjson.com',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      defaultTtl: const Duration(minutes: 5),
    ),
  ));

  // Register feature blocs
  // PostsBloc uses leased (fetches fresh on each visit)
  // CoalesceBloc and InterceptorsBloc use permanent (state persists across navigation)

  if (!BlocScope.isRegistered<PostsBloc>()) {
    BlocScope.register<PostsBloc>(
      () => PostsBloc(fetchBloc: fetchBloc),
      lifecycle: BlocLifecycle.leased,
    );
  }

  if (!BlocScope.isRegistered<CoalesceBloc>()) {
    BlocScope.register<CoalesceBloc>(
      () => CoalesceBloc(fetchBloc: fetchBloc),
      lifecycle: BlocLifecycle.permanent,
    );
  }

  if (!BlocScope.isRegistered<InterceptorsBloc>()) {
    BlocScope.register<InterceptorsBloc>(
      () => InterceptorsBloc(fetchBloc: fetchBloc),
      lifecycle: BlocLifecycle.permanent,
    );
  }

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
