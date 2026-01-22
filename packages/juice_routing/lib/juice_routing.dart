/// Declarative, state-driven navigation for Juice applications.
///
/// juice_routing provides Navigator 2.0 integration with route guards,
/// deep linking support, and automatic scope management.
///
/// ## Quick Start
///
/// ```dart
/// // 1. Define routes
/// final config = RoutingConfig(
///   routes: [
///     RouteConfig(
///       path: '/',
///       builder: (ctx) => HomeScreen(),
///     ),
///     RouteConfig(
///       path: '/profile/:userId',
///       builder: (ctx) => ProfileScreen(userId: ctx.params['userId']!),
///       guards: [AuthGuard()],
///     ),
///   ],
/// );
///
/// // 2. Register and initialize
/// BlocScope.register<RoutingBloc>(
///   () => RoutingBloc(),
///   lifecycle: BlocLifecycle.permanent,
/// );
/// final routingBloc = BlocScope.get<RoutingBloc>();
/// routingBloc.send(InitializeRoutingEvent(config: config));
///
/// // 3. Use with MaterialApp.router
/// MaterialApp.router(
///   routerDelegate: JuiceRouterDelegate(routingBloc: routingBloc),
///   routeInformationParser: const JuiceRouteInformationParser(),
/// );
///
/// // 4. Navigate
/// routingBloc.navigate('/profile/123');
/// ```
///
/// ## Contract Guarantees
///
/// - **Atomicity**: Navigation either commits fully or not at all
/// - **Concurrency**: One pending navigation; new ones queue (latest wins)
/// - **Redirect cap**: Max 5 redirects before [RedirectLoopError]
/// - **Guard errors**: Exception → [GuardExceptionError], navigation aborted
/// - **Pop behavior**: Pop events bypass guards, execute immediately
library juice_routing;

// Core types
export 'src/routing_types.dart';
export 'src/routing_errors.dart';

// Guards
export 'src/route_guard.dart';
export 'src/route_context.dart';

// Configuration
export 'src/routing_config.dart';

// State and events
export 'src/routing_state.dart';
export 'src/routing_events.dart';

// Bloc
export 'src/routing_bloc.dart';

// Path resolution
export 'src/path_resolver.dart';

// Navigator 2.0 integration
export 'src/navigator/route_path.dart';
export 'src/navigator/juice_route_parser.dart';
export 'src/navigator/juice_router_delegate.dart';
export 'src/navigator/visibility_observer.dart';
