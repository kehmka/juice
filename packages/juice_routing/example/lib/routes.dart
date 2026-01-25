import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

import 'auth_bloc.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/aviator_demo_screen.dart';
import 'screens/demo_screen.dart';
import 'screens/playground_screen.dart';

/// Auth guard that redirects to login if not authenticated
class AuthGuard extends RouteGuard {
  @override
  String get name => 'AuthGuard';

  @override
  int get priority => 10; // Run early

  @override
  Future<GuardResult> check(RouteContext context) async {
    final authBloc = BlocScope.get<AuthBloc>();

    if (authBloc.state.isLoggedIn) {
      return const GuardResult.allow();
    }

    // Redirect to login with return path
    return GuardResult.redirect(
      '/login',
      returnTo: context.targetPath,
    );
  }
}

/// Guest guard that redirects away from login if already authenticated
class GuestGuard extends RouteGuard {
  @override
  String get name => 'GuestGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    final authBloc = BlocScope.get<AuthBloc>();

    if (!authBloc.state.isLoggedIn) {
      return const GuardResult.allow();
    }

    // Already logged in, redirect to home
    return const GuardResult.redirect('/');
  }
}

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
      builder: (ctx) => const HomeScreen(),
    ),

    // Aviator demo - public
    RouteConfig(
      path: '/aviator-demo',
      title: 'Aviator Demo',
      builder: (ctx) => const AviatorDemoScreen(),
    ),

    // Demo screen for navigation type testing
    RouteConfig(
      path: '/demo',
      title: 'Demo',
      builder: (ctx) => const DemoScreen(),
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
      guards: [GuestGuard()],
      transition: RouteTransition.fade,
    ),

    // Profile - requires auth, has parameter
    RouteConfig(
      path: '/profile/:userId',
      title: 'Profile',
      builder: (ctx) => ProfileScreen(
        userId: ctx.params['userId']!,
      ),
      guards: [AuthGuard()],
      transition: RouteTransition.slideRight,
    ),

    // Settings - requires auth, has nested routes
    RouteConfig(
      path: '/settings',
      title: 'Settings',
      builder: (ctx) => const SettingsScreen(),
      guards: [AuthGuard()],
      children: [
        RouteConfig(
          path: 'account',
          title: 'Account Settings',
          builder: (ctx) => const SettingsScreen(section: 'account'),
        ),
        RouteConfig(
          path: 'privacy',
          title: 'Privacy Settings',
          builder: (ctx) => const SettingsScreen(section: 'privacy'),
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
    builder: (ctx) => const NotFoundScreen(),
  ),

  initialPath: '/',
  maxRedirects: 5,
);
