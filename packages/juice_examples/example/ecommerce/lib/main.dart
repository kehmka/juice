import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import 'package:juice_network/juice_network.dart';
import 'package:juice_routing/juice_routing.dart';
import 'blocs/products_bloc.dart';
import 'blocs/cart_bloc.dart';
import 'screens/products_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/checkout_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Storage for cart persistence and network cache
  BlocScope.register<StorageBloc>(
    () => StorageBloc(
      config: const StorageConfig(
        hiveBoxesToOpen: ['cart', 'fetch_cache'],
      ),
    ),
  );
  final storageBloc = BlocScope.get<StorageBloc>();
  await storageBloc.initialize();

  // FetchBloc for network requests
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

  // Routing
  BlocScope.register<RoutingBloc>(
    () => RoutingBloc.withConfig(
      RoutingConfig(
        initialPath: '/products',
        routes: [
          RouteConfig(
            path: '/products',
            builder: (_) => const ProductsScreen(),
          ),
          RouteConfig(
            path: '/products/:id',
            builder: (_) => const ProductDetailScreen(),
          ),
          RouteConfig(
            path: '/cart',
            builder: (_) => CartScreen(),
          ),
          RouteConfig(
            path: '/checkout',
            builder: (_) => CheckoutScreen(),
          ),
        ],
      ),
    ),
  );

  // App blocs
  BlocScope.register<ProductsBloc>(
    () => ProductsBloc(fetchBloc: fetchBloc),
  );
  BlocScope.register<CartBloc>(() => CartBloc());

  runApp(const EcommerceApp());
}

class EcommerceApp extends StatelessWidget {
  const EcommerceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final routingBloc = BlocScope.get<RoutingBloc>();

    return MaterialApp.router(
      title: 'Juice Shop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      routerDelegate: JuiceRouterDelegate(routingBloc: routingBloc),
      routeInformationParser: const JuiceRouteInformationParser(),
    );
  }
}
