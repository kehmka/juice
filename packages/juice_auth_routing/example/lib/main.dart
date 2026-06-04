import 'package:juice/juice.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_auth_routing/juice_auth_routing.dart';
import 'package:juice_routing/juice_routing.dart';
import 'package:juice_storage/juice_storage.dart';

import 'demo_auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageBloc = StorageBloc(config: const StorageConfig());
  await storageBloc.initialize();

  final authBloc = AuthBloc.withConfig(
    AuthConfig(
      providers: {'email': DemoAuthProvider()},
      restoreSessionOnInit: false,
    ),
    storageBloc: storageBloc,
  );

  final routingBloc = RoutingBloc.withConfig(
    RoutingConfig(
      routes: [
        RouteConfig(path: '/', builder: (_) => const HomeScreen()),
        RouteConfig(
          path: '/login',
          builder: (_) => const LoginScreen(),
          guards: [AuthBlocGuestGuard(authBloc)], // bounce if already logged in
        ),
        RouteConfig(
          path: '/profile',
          builder: (_) => ProfileScreen(),
          guards: [AuthBlocAuthGuard(authBloc)], // require auth
        ),
      ],
      initialPath: '/',
    ),
  );

  BlocScope.register<AuthBloc>(() => authBloc, lifecycle: BlocLifecycle.permanent);
  BlocScope.register<RoutingBloc>(() => routingBloc,
      lifecycle: BlocLifecycle.permanent);

  // Evict to /login if the session ends while on a protected route.
  AuthBlocRoutingBridge(authBloc, routingBloc).start();

  runApp(DemoApp(routingBloc: routingBloc));
}

class DemoApp extends StatelessWidget {
  final RoutingBloc routingBloc;
  const DemoApp({super.key, required this.routingBloc});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'juice_auth_routing demo',
      debugShowCheckedModeBanner: false,
      routerDelegate: JuiceRouterDelegate(routingBloc: routingBloc),
      routeInformationParser: const JuiceRouteInformationParser(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: FilledButton(
          onPressed: () => BlocScope.get<RoutingBloc>().navigate('/profile'),
          child: const Text('Go to Profile (protected)'),
        ),
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: FilledButton(
          onPressed: () {
            BlocScope.get<AuthBloc>().loginWithEmail('ada@demo.dev', 'pw');
            BlocScope.get<RoutingBloc>().navigate('/profile');
          },
          child: const Text('Log in'),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessJuiceWidget<AuthBloc> {
  ProfileScreen({super.key}) : super(groups: {AuthGroups.status});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Signed in as ${bloc.state.user?.displayName}'),
            const SizedBox(height: 16),
            // Logout → the bridge redirects this protected screen to /login.
            OutlinedButton(
              onPressed: () => bloc.logout(force: true),
              child: const Text('Log out'),
            ),
          ],
        ),
      ),
    );
  }
}
