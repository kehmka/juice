import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

import 'routes.dart';
import 'auth_bloc.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final RoutingBloc _routingBloc;
  late final JuiceRouterDelegate _routerDelegate;

  @override
  void initState() {
    super.initState();

    // Register AuthBloc globally
    BlocScope.register<AuthBloc>(
      () => AuthBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // Register RoutingBloc globally
    BlocScope.register<RoutingBloc>(
      () => RoutingBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // Get instances
    _routingBloc = BlocScope.get<RoutingBloc>();

    // Initialize routing with config
    _routingBloc.send(InitializeRoutingEvent(config: appRoutes));

    // Create router delegate
    _routerDelegate = JuiceRouterDelegate(routingBloc: _routingBloc);
  }

  @override
  void dispose() {
    _routerDelegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Juice Routing Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      routerDelegate: _routerDelegate,
      routeInformationParser: const JuiceRouteInformationParser(),
    );
  }
}
