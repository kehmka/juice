import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import 'package:juice_network/juice_network.dart';
import 'blocs/feed_bloc.dart';
import 'blocs/profile_bloc.dart';
import 'screens/feed_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Storage for network cache
  BlocScope.register<StorageBloc>(
    () => StorageBloc(
      config: const StorageConfig(hiveBoxesToOpen: ['fetch_cache']),
    ),
  );
  final storageBloc = BlocScope.get<StorageBloc>();
  await storageBloc.initialize();

  // FetchBloc with dummyjson.com base URL
  BlocScope.register<FetchBloc>(
    () => FetchBloc(storageBloc: storageBloc),
  );
  final fetchBloc = BlocScope.get<FetchBloc>();
  await fetchBloc.send(InitializeFetchEvent(
    config: const FetchConfig(
      defaultCachePolicy: CachePolicy.staleWhileRevalidate,
      defaultTtl: Duration(minutes: 5),
    ),
  ));

  // App blocs
  BlocScope.register<FeedBloc>(
    () => FeedBloc(fetchBloc: fetchBloc),
  );
  BlocScope.register<ProfileBloc>(
    () => ProfileBloc(fetchBloc: fetchBloc),
  );

  runApp(const SocialFeedApp());
}

class SocialFeedApp extends StatelessWidget {
  const SocialFeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Juice Social Feed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.pink,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.pink,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: FeedScreen(),
    );
  }
}
