---
card_schema: "1.0"
package: juice_routing
version: 1.1.0
requires:
  juice: ">=1.4.0"
updated: 2026-06-09
---

# juice_routing — AI card

> Declarative, state-driven navigation: routes + guards + a `RoutingBloc` whose
> immutable stack drives a Navigator 2.0 `RouterDelegate`. Substrate package.
> Read repo `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** the navigation stack as bloc state, route matching/params, the guard
pipeline (allow/redirect/block), history, and Navigator 2.0 integration
(`JuiceRouterDelegate` + `JuiceRouteInformationParser`).
**Does NOT own:** *why* a guard allows/blocks (you supply the predicate or use
`juice_auth_routing`), screen widgets, or deep-link platform plumbing beyond URL
parsing.

## Install

```yaml
dependencies:
  juice_routing: ^1.1.0
```

No platform setup. Optionally register `ScopeLifecycleBloc` (core juice) so a
`RouteConfig.scopeName` activates a feature scope on entry.

## Construct

```dart
final routing = RoutingBloc.withConfig(
  RoutingConfig(
    routes: [
      RouteConfig(path: '/',               builder: (ctx) => HomeScreen()),
      RouteConfig(path: '/login',          builder: (ctx) => LoginScreen()),
      RouteConfig(path: '/profile/:userId',
        builder: (ctx) => ProfileScreen(userId: ctx.params['userId']!),
        guards: [AuthGuard(isAuthenticated: () => loggedIn)]),
    ],
    globalGuards: [],          // run before route guards, every navigation
    notFoundRoute: null,       // null → RouteNotFoundError instead of a 404 screen
    initialPath: '/', maxRedirects: 5, maxHistorySize: 100,
  ),
  initialPath: '/',           // optional override
);

MaterialApp.router(
  routerDelegate: JuiceRouterDelegate(routingBloc: routing),
  routeInformationParser: const JuiceRouteInformationParser(),
);
```

## Seams

```dart
// Implement a guard (or use the shipped AuthGuard / GuestGuard / RoleGuard,
// or juice_auth_routing's AuthBloc-wired variants).
abstract class RouteGuard {
  String get name => runtimeType.toString();
  int get priority => 100;                       // lower runs first
  Future<GuardResult> check(RouteContext context);
}
// GuardResult: GuardResult.allow()
//            | GuardResult.redirect(path, returnTo?)   // restarts navigation
//            | GuardResult.block(reason?)              // aborts → GuardBlockedError
// RouteContext: targetPath, params, query, currentState, targetRoute
```

## API

`RoutingBloc` (thin wrappers over events; `bloc.state` is the stack):

```dart
factory RoutingBloc.withConfig(RoutingConfig config, {String? initialPath});
void navigate(String path, {Object? extra, bool replace = false});   // guards run
void pop({Object? result});                                          // bypasses guards
void popUntil(bool Function(StackEntry) predicate);                  // bypasses guards
void popToRoot();                                                    // bypasses guards
void resetStack(String path, {Object? extra});                      // guards run on new path
RoutingConfig get config; PathResolver get pathResolver;
```

## Events

| Event | Effect |
|---|---|
| `InitializeRoutingEvent(config, initialPath?)` | resolve initial path, build initial stack |
| `NavigateEvent(path, extra?, replace?, transition?)` | run guards → push (or replace) |
| `PopEvent(result?)` | pop top; **bypasses guards**; `CannotPopError` at root |
| `PopUntilEvent(predicate)` | pop until predicate true; bypasses guards |
| `PopToRootEvent()` | clear to first entry; bypasses guards |
| `ResetStackEvent(path, extra?)` | run guards on `path`, replace whole stack |
| `RouteVisibleEvent(routeKey)` / `RouteHiddenEvent(routeKey)` *internal* | time-on-route, sent by the navigator observer |

## State

```dart
class RoutingState extends BlocState {            // immutable
  List<StackEntry> stack;                         // index 0 = bottom
  PendingNavigation? pending;                      // non-null while guards run
  List<HistoryEntry> history; RoutingError? error; bool isInitialized;
  StackEntry? get current; String? get currentPath;
  bool get isNavigating; bool get canPop; int get stackDepth;
}
// StackEntry: route, path, params, query, extra, key (identity), pushedAt, scopeId
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `RoutingGroups.stack` → `routing.stack` | push / pop / replace / reset |
| `RoutingGroups.current` → `routing.current` | top entry changed |
| `RoutingGroups.pending` → `routing.pending` | guard run starts/ends |
| `RoutingGroups.history` → `routing.history` | history appended/trimmed |
| `RoutingGroups.error` → `routing.error` | a `RoutingError` occurred |

## Concurrency

Navigation is single-flight by a manual guard, not `EventConcurrency`: while one
`NavigateEvent` is resolving (`state.pending != null`), a newer one is stashed via
`queueNavigation` and run after — **latest wins**, at most one pending. `Pop*`
events bypass guards and execute immediately.

## Recipes

```dart
// 1. A guard (sync or async predicate).
class FeatureFlagGuard extends RouteGuard {
  FeatureFlagGuard(this.enabled);
  final bool Function() enabled;
  @override Future<GuardResult> check(RouteContext c) async =>
      enabled() ? const GuardResult.allow() : const GuardResult.block(reason: 'off');
}

// 2. Bind a widget to the current route.
class Crumb extends StatelessJuiceWidget<RoutingBloc> {
  Crumb({super.key}) : super(groups: {RoutingGroups.current});
  @override Widget onBuild(BuildContext c, StreamStatus s) => Text(bloc.state.currentPath ?? '/');
}

// 3. Post-login redirect using returnTo captured by AuthGuard.
//    AuthGuard redirects to '/login?returnTo=/profile'; after login:
routing.resetStack(returnTo ?? '/');
```

## Testing

Headless — drive the bloc, assert on `state.stack` / `state.error`.

```dart
final routing = RoutingBloc.withConfig(RoutingConfig(routes: [
  RouteConfig(path: '/', builder: (_) => const SizedBox()),
  RouteConfig(path: '/a', builder: (_) => const SizedBox(), guards: [denyGuard]),
]));
await settle();
routing.navigate('/a');
await settle();
expect(routing.state.currentPath, '/');                 // blocked, stayed put
expect(routing.state.error, isA<GuardBlockedError>());
```

## Failure modes

- Errors are a sealed `RoutingError`: `RouteNotFoundError` (no match + no
  `notFoundRoute`), `GuardBlockedError` (a `block()`), `GuardExceptionError` (a
  guard *threw* — navigation aborts), `RedirectLoopError` (> `maxRedirects`),
  `InvalidPathError`, `CannotPopError` (pop at root).
- A navigation either commits fully or not at all (atomic) — on guard
  block/exception the stack is unchanged and `state.error` is set.
- A guard returning `redirect(path)` restarts the pipeline against `path`,
  counting toward `maxRedirects`.

## Anti-patterns

- ❌ Putting auth logic inside route widgets — express it as a guard so it runs
  before the screen builds.
- ❌ Expecting `pop()` to honor guards — pops bypass guards by contract.
- ❌ Throwing from a guard for an expected denial — return `block()`/`redirect()`;
  a throw becomes `GuardExceptionError`.
- ❌ Mutating `RoutingState.stack` directly — navigate via events only.

## Integrates with

- **juice_auth** via **juice_auth_routing** — `AuthBlocAuthGuard`,
  `AuthBlocGuestGuard`, `AuthBlocRoleGuard`, and `AuthBlocRoutingBridge` (reactive
  eviction when a session ends mid-route).
- **juice** `ScopeLifecycleBloc` — `RouteConfig.scopeName` ties a route to a
  feature scope.

## Invariants

- `StackEntry` identity is its `key` (used for Navigator reconciliation and `==`).
- One pending navigation at a time; newer navigations supersede the queued one.
- `history` is bounded by `maxHistorySize` (oldest trimmed).

## See also

`doc/SPEC.md` · `doc/guards.md` · `doc/routes.md` · `doc/deep-links.md` ·
repo `AGENTS.md` (framework).
