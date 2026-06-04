/// Integration glue between [juice_auth](https://pub.dev/packages/juice_auth)
/// and [juice_routing](https://pub.dev/packages/juice_routing).
///
/// Feeds `AuthBloc` state into routing's guard system, two ways:
///
/// - **Guards** (evaluated on navigation): `AuthBlocAuthGuard`,
///   `AuthBlocGuestGuard`, `AuthBlocRoleGuard`.
/// - **Reactive redirect** (auth changes mid-session): `AuthBlocRoutingBridge`.
///
/// ```dart
/// final routing = RoutingBloc.withConfig(RoutingConfig(routes: [
///   RouteConfig('/profile', builder: ..., guards: [AuthBlocAuthGuard(authBloc)]),
///   RouteConfig('/login',   builder: ..., guards: [AuthBlocGuestGuard(authBloc)]),
/// ]));
///
/// // Evict on logout/expiry even while sitting on a protected route:
/// AuthBlocRoutingBridge(authBloc, routing)..start();
/// ```
library juice_auth_routing;

export 'src/auth_bloc_auth_guard.dart';
export 'src/auth_bloc_guest_guard.dart';
export 'src/auth_bloc_role_guard.dart';
export 'src/auth_bloc_routing_bridge.dart';
