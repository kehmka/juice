import 'package:juice/juice.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_network/juice_network.dart';
import 'package:juice_storage/juice_storage.dart';

import 'demo_wiring.dart';
import 'home_screen.dart';
import 'profile_bloc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageBloc = StorageBloc(
    config: const StorageConfig(hiveBoxesToOpen: [CacheManager.cacheBoxName]),
  );
  await storageBloc.initialize();

  final blocs = await buildDemo(storageBloc: storageBloc);

  // Register so StatelessJuiceWidget can resolve them.
  BlocScope.register<AuthBloc>(() => blocs.authBloc,
      lifecycle: BlocLifecycle.permanent);
  BlocScope.register<FetchBloc>(() => blocs.fetchBloc,
      lifecycle: BlocLifecycle.permanent);
  BlocScope.register<ProfileBloc>(() => blocs.profileBloc,
      lifecycle: BlocLifecycle.permanent);

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'juice_auth_network demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}
