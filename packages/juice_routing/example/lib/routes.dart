import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

import 'auth_bloc.dart';
import 'screens/admin_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/aviator_demo_screen.dart';
import 'screens/demo_screen.dart';
import 'screens/playground_screen.dart';

bool _isAuthenticated() => BlocScope.get<AuthBloc>().state.isLoggedIn;

/// Logging guard that logs all navigation (for demo purposes)
class LoggingGuard extends RouteGuard {
  @override
  String get name => 'LoggingGuard';

  @override
  int get priority => 1; // Run first

  @override
  Future<GuardResult> check(RouteContext context) async {
    print('[Navigation] ${context.targetPath}');
    return const GuardResult.allow();
  }
}

/// App route configuration
final appRoutes = RoutingConfig(
  routes: [
    // Home - public
    RouteConfig(
      path: '/',
      title: 'Home',
      builder: (ctx) => HomeScreen(),
    ),

    // Aviator demo - public
    RouteConfig(
      path: '/aviator-demo',
      title: 'Aviator Demo',
      builder: (ctx) => AviatorDemoScreen(),
    ),

    // Demo screen for navigation type testing
    RouteConfig(
      path: '/demo',
      title: 'Demo',
      builder: (ctx) => DemoScreen(),
    ),

    // Navigation playground - parameterized depth
    RouteConfig(
      path: '/playground/:depth',
      title: 'Playground',
      builder: (ctx) => PlaygroundScreen(
        depth: int.tryParse(ctx.params['depth'] ?? '1') ?? 1,
      ),
    ),

    // Login - only for guests
    RouteConfig(
      path: '/login',
      title: 'Login',
      builder: (ctx) => const LoginScreen(),
      guards: [const GuestGuard(isAuthenticated: _isAuthenticated)],
      transition: RouteTransition.fade,
    ),

    // Profile - requires auth, has parameter
    RouteConfig(
      path: '/profile/:userId',
      title: 'Profile',
      builder: (ctx) => ProfileScreen(
        userId: ctx.params['userId']!,
      ),
      guards: [const AuthGuard(isAuthenticated: _isAuthenticated)],
      transition: RouteTransition.slideRight,
    ),

    // Settings - requires auth, has nested routes
    RouteConfig(
      path: '/settings',
      title: 'Settings',
      builder: (ctx) => SettingsScreen(),
      guards: [const AuthGuard(isAuthenticated: _isAuthenticated)],
      children: [
        RouteConfig(
          path: 'account',
          title: 'Account Settings',
          builder: (ctx) => SettingsScreen(section: 'account'),
        ),
        RouteConfig(
          path: 'privacy',
          title: 'Privacy Settings',
          builder: (ctx) => SettingsScreen(section: 'privacy'),
        ),
      ],
    ),

    // Admin - requires auth + admin role
    RouteConfig(
      path: '/admin',
      title: 'Admin Panel',
      builder: (ctx) => AdminScreen(),
      guards: [
        const AuthGuard(isAuthenticated: _isAuthenticated),
        RoleGuard(
          hasRole: () => BlocScope.get<AuthBloc>().state.isAdmin,
          roleName: 'admin',
        ),
      ],
    ),
  ],

  // Global guards run on every navigation
  globalGuards: [
    LoggingGuard(),
  ],

  // Fallback for unknown routes
  notFoundRoute: RouteConfig(
    path: '/404',
    title: 'Not Found',
    builder: (ctx) => NotFoundScreen(),
  ),

  initialPath: '/',
  maxRedirects: 5,
  maxHistorySize: 50,
);
