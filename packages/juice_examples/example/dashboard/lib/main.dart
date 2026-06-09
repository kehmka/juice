import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_routing/juice_routing.dart';
import 'auth/dashboard_auth_provider.dart';
import 'blocs/dashboard_bloc.dart';
import 'blocs/analytics_bloc.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/users_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Storage for auth token persistence
  BlocScope.register<StorageBloc>(
    () => StorageBloc(config: const StorageConfig()),
  );
  final storageBloc = BlocScope.get<StorageBloc>();
  await storageBloc.initialize();

  // Auth with fake provider
  BlocScope.register<AuthBloc>(
    () => AuthBloc(storageBloc: storageBloc),
  );
  final authBloc = BlocScope.get<AuthBloc>();
  await authBloc.send(InitializeAuthEvent(
    config: AuthConfig(
      providers: {'email': DashboardAuthProvider()},
      restoreSessionOnInit: true,
    ),
  ));

  // Routing with guards
  BlocScope.register<RoutingBloc>(
    () => RoutingBloc.withConfig(
      RoutingConfig(
        initialPath: '/login',
        routes: [
          RouteConfig(
            path: '/login',
            builder: (_) => const LoginScreen(),
            guards: [
              GuestGuard(
                isAuthenticated: () => authBloc.state.isAuthenticated,
                redirectPath: '/dashboard',
              ),
            ],
          ),
          RouteConfig(
            path: '/dashboard',
            builder: (_) => DashboardScreen(),
            guards: [
              AuthGuard(
                isAuthenticated: () => authBloc.state.isAuthenticated,
              ),
            ],
          ),
          RouteConfig(
            path: '/analytics',
            builder: (_) => AnalyticsScreen(),
            guards: [
              AuthGuard(
                isAuthenticated: () => authBloc.state.isAuthenticated,
              ),
              RoleGuard(
                hasRole: () => authBloc.state.hasRole('admin'),
                roleName: 'admin',
              ),
            ],
          ),
          RouteConfig(
            path: '/users',
            builder: (_) => const UsersScreen(),
            guards: [
              AuthGuard(
                isAuthenticated: () => authBloc.state.isAuthenticated,
              ),
              RoleGuard(
                hasRole: () => authBloc.state.hasRole('admin'),
                roleName: 'admin',
              ),
            ],
          ),
          RouteConfig(
            path: '/settings',
            builder: (_) => const SettingsScreen(),
            guards: [
              AuthGuard(
                isAuthenticated: () => authBloc.state.isAuthenticated,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // Dashboard blocs
  BlocScope.register<DashboardBloc>(() => DashboardBloc());
  BlocScope.register<AnalyticsBloc>(() => AnalyticsBloc());

  runApp(const DashboardApp());
}

class DashboardApp extends StatelessWidget {
  const DashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final routingBloc = BlocScope.get<RoutingBloc>();

    return MaterialApp.router(
      title: 'Juice Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      routerDelegate: JuiceRouterDelegate(routingBloc: routingBloc),
      routeInformationParser: const JuiceRouteInformationParser(),
    );
  }
}
