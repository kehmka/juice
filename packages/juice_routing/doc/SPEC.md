# juice_routing Specification

> **Status:** Draft v0.2 (pre-freeze)
> **Package:** `juice_routing`
> **Primary Bloc:** `RoutingBloc`

## Overview

**juice_routing** provides declarative, state-driven navigation for Juice applications. While Flutter's Navigator is imperative ("push this, pop that"), RoutingBloc makes navigation reactive and observable—routes become state, guards become use cases, and deep links flow through the same event system as everything else.

---

## Dependencies

| Package | Dependency | Purpose |
|---------|------------|---------|
| `juice` | Required | Core bloc infrastructure, BlocScope, ScopeLifecycleBloc (for scope integration) |
| `flutter` | Required | Navigator 2.0 integration |

**No dependency on `juice_storage` or `juice_network`.** Those are peer packages, not prerequisites.

**ScopeLifecycleBloc integration** is optional at runtime—if you don't configure route scopes, the feature is inactive.

---

## Why Use RoutingBloc?

> **Navigator is imperative. RoutingBloc is declarative.**
>
> It makes navigation state-driven, guarded, observable, deep-link-aware, and testable—without fighting Flutter's navigation system.

---

### The 6 Problems With "Just Navigator"

Every team without a navigation foundation ends up with:

```dart
// Scattered across your codebase:
class HomeScreen extends StatelessWidget {
  void _goToProfile() {
    Navigator.push(context, MaterialPageRoute(  // Imperative
      builder: (_) => ProfileScreen(),
    ));
  }

  void _goToSettings() {
    if (authService.isLoggedIn) {  // Guard logic here...
      Navigator.pushNamed(context, '/settings');
    } else {
      Navigator.pushNamed(context, '/login');  // ...and here
    }
  }
}

// Deep link handling somewhere else entirely:
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateRoute: (settings) {
        // 500 lines of route matching...
      },
    );
  }
}
```

**This creates real bugs:**

| # | Problem | What Goes Wrong |
|---|---------|-----------------|
| 1 | **Imperative push/pop** | Navigation state scattered, hard to reason about "where am I?" |
| 2 | **Guards everywhere** | Auth checks copy-pasted into every navigation call |
| 3 | **Deep link chaos** | `/profile/123` works from browser but breaks in-app |
| 4 | **No history** | "What screens did the user visit?" requires manual tracking |
| 5 | **Untestable** | Can't unit test navigation logic without widget tests |
| 6 | **Scope leaks** | Navigate away but blocs/subscriptions linger |

### The 6 Things RoutingBloc Adds

| # | Capability | What It Does |
|---|------------|--------------|
| 1 | **Declarative routes** | Route config as data, not scattered `push()` calls |
| 2 | **Route guards** | Async guards as use cases—auth, onboarding, permissions |
| 3 | **Deep link unification** | Same path resolution for cold start, warm start, in-app |
| 4 | **Observable state** | Current route, stack, params all in `RoutingState` |
| 5 | **Testable** | Mock events, assert state—no widget tests needed |
| 6 | **Scope integration** | Navigate away → `FeatureScope.end()` → cleanup |

```dart
// One place, consistent behavior:
routingBloc.send(NavigateEvent(
  path: '/profile/123',
  transition: RouteTransition.slideRight,
));

// Guards run automatically via use cases
// Deep links resolve through same path
// State updates, widgets rebuild
```

**And in your UI:**

```dart
// RouterDelegate reads RoutingBloc state
class JuiceRouterDelegate extends RouterDelegate<RoutePath> {
  final RoutingBloc routingBloc;

  @override
  Widget build(BuildContext context) {
    return StatelessJuiceWidget<RoutingBloc>(
      groups: const {'routing:stack'},
      builder: (context, status) {
        return Navigator(
          pages: routingBloc.state.stack.map(_buildPage).toList(),
          onPopPage: (route, result) {
            routingBloc.send(PopEvent(result: result));
            return route.didPop(result);
          },
        );
      },
    );
  }
}
```

### Side-by-Side Comparison

| Concern | Just Navigator | RoutingBloc |
|---------|----------------|-------------|
| **Navigation** | `Navigator.push()` everywhere | `NavigateEvent` with path |
| **Guards** | `if (auth)` before each push | `RouteGuard` use cases |
| **Deep links** | Custom `onGenerateRoute` | Unified path resolution |
| **Current route** | `ModalRoute.of(context)` | `routingBloc.state.currentRoute` |
| **History** | Manual tracking | `routingBloc.state.history` |
| **Testing** | Widget tests only | Unit test events/state |
| **Cleanup** | Manual dispose | Auto scope integration |
| **Analytics** | Manual logging | Event stream subscription |

---

## Foundation Contract

RoutingBloc guarantees these behaviors:

### A. Navigation Atomicity

**A `NavigateEvent` either results in a single committed stack mutation or no mutation.**

There are no partial states. If guards block or an error occurs, the stack remains unchanged.

### B. Concurrent Navigation

**If a navigation is pending (guards running), new navigation events are queued.**

- Queue depth: 1 (latest wins, previous queued event is dropped)
- Pop events are NOT queued—they execute immediately (no guards)
- This prevents race conditions from rapid user taps

### C. Redirect Loop Cap

**A redirect chain is capped at 5 to prevent infinite loops.**

If guard A redirects to B, and B redirects to A, the chain terminates after 5 hops with a `RedirectLoopError`.

### D. Guard Error Policy

**Guard exceptions become `GuardExceptionError` and navigation is aborted.**

The stack does not change. The error is captured in `RoutingState.lastError` and emitted with `routing:error` group.

### E. Declarative Route Configuration

Routes defined as data, not imperative callbacks:

```dart
final routes = [
  RouteConfig(
    path: '/',
    builder: (ctx) => HomeScreen(),
  ),
  RouteConfig(
    path: '/profile/:userId',
    builder: (ctx) => ProfileScreen(userId: ctx.params['userId']!),
    guards: [AuthGuard()],
  ),
  RouteConfig(
    path: '/settings',
    builder: (ctx) => SettingsScreen(),
    guards: [AuthGuard(), OnboardingGuard()],
    children: [
      RouteConfig(path: 'appearance', builder: (ctx) => AppearanceScreen()),
      RouteConfig(path: 'privacy', builder: (ctx) => PrivacyScreen()),
    ],
  ),
];
```

### F. Path Resolution

Consistent path matching with parameters:

| Pattern | Matches | Params |
|---------|---------|--------|
| `/profile/:id` | `/profile/123` | `{id: '123'}` |
| `/users/:userId/posts/:postId` | `/users/5/posts/42` | `{userId: '5', postId: '42'}` |
| `/search` | `/search?q=flutter` | query: `{q: 'flutter'}` |
| `/files/*` | `/files/a/b/c` | `{*: 'a/b/c'}` (wildcard) |

### G. Guard Execution Model

**When guards run:**
- `NavigateEvent` (push): YES
- `NavigateEvent` with `replace: true`: YES
- `ResetStackEvent`: YES
- `PopEvent`: NO (pop is always allowed)
- `PopUntilEvent`: NO
- `PopToRootEvent`: NO

**Execution order:**
1. Resolve path → target route + params + query
2. Run **global guards** in priority order (lower priority number = first)
3. Run **route guards** in priority order
4. First non-allow result wins
5. Redirect restarts the pipeline from step 1 (with loop counter)

**Guard capabilities:**
- Guards receive `RouteContext` with target path, params, query, current state
- Guards **cannot** mutate params or query
- Redirect does **NOT** preserve `extra` (new navigation, new context)
- Guards can be async (token refresh, permission check, etc.)

### H. Stack Management

Navigation stack is explicit state:

```dart
// Push
routingBloc.send(NavigateEvent(path: '/detail'));

// Replace
routingBloc.send(NavigateEvent(path: '/home', replace: true));

// Pop (no guards, immediate)
routingBloc.send(PopEvent());

// Pop to root (no guards)
routingBloc.send(PopToRootEvent());

// Reset stack (guards run on new root)
routingBloc.send(ResetStackEvent(path: '/login'));
```

### I. Transition Control

Route transitions are configurable per-navigation or per-route:

```dart
routingBloc.send(NavigateEvent(
  path: '/detail',
  transition: RouteTransition.slideRight,
  duration: Duration(milliseconds: 300),
));
```

### J. One RoutingBloc Per Navigator

**Each Navigator has its own RoutingBloc instance.**

- `RoutingBloc` for root app navigation
- Separate `RoutingBloc` instances for nested navigators (tabs, shells)
- All share the same `PathResolver` implementation and guard types
- This keeps state management simple and avoids multi-stack complexity in one bloc

```dart
// Root
BlocScope.register<RoutingBloc>(
  () => RoutingBloc(config: appConfig),
  lifecycle: BlocLifecycle.permanent,
);

// Nested tab navigator (scoped)
BlocScope.register<RoutingBloc>(
  () => RoutingBloc(config: homeTabConfig),
  lifecycle: BlocLifecycle.feature,
  scope: 'home-tab',
);
```

---

## State Model

### RoutingState

```dart
@immutable
class RoutingState extends BlocState {
  /// Whether the bloc is initialized with routes
  final bool isInitialized;

  /// Current navigation stack
  final List<StackEntry> stack;

  /// Navigation history (bounded)
  final List<HistoryEntry> history;

  /// Pending navigation (during guard execution)
  final PendingNavigation? pending;

  /// Last navigation error
  final RoutingError? lastError;

  /// Active scope IDs from current stack (keyed by entry, not name)
  final Set<String> activeScopeIds;

  // Convenience getters
  StackEntry? get current => stack.lastOrNull;
  String get currentPath => current?.path ?? '/';
  Map<String, String> get currentParams => current?.params ?? {};
  bool get canPop => stack.length > 1;
}
```

### StackEntry

```dart
@immutable
class StackEntry {
  /// Resolved route configuration
  final RouteConfig route;

  /// Full path including params
  final String path;

  /// Extracted path parameters
  final Map<String, String> params;

  /// Query parameters
  final Map<String, String> query;

  /// Non-URL state passed via NavigateEvent
  final Object? extra;

  /// Unique key for this stack entry (identity, not name)
  final String key;

  /// Scope ID if this entry owns a scope (unique per entry)
  final String? scopeId;

  /// When this entry was pushed
  final DateTime pushedAt;

  /// Custom page for Navigator 2.0
  Page<dynamic> toPage(Widget child);
}
```

**Scope identity:** `scopeId` is unique per `StackEntry`, not per route name. If you push `/checkout` twice, each gets a distinct `scopeId`. This prevents scope collision.

### HistoryEntry

```dart
@immutable
class HistoryEntry {
  final String path;
  final DateTime timestamp;
  final NavigationType type; // push, pop, replace, reset
  final Duration? timeOnRoute;
}
```

**Time-on-route measurement:** Computed by `JuiceRouterDelegate` via `NavigatorObserver` when routes become visible/hidden. `RouteVisibleEvent` and `RouteHiddenEvent` are emitted by the delegate, not guessed.

### PendingNavigation

```dart
@immutable
class PendingNavigation {
  final String targetPath;
  final int guardsCompleted;
  final int totalGuards;
  final RouteGuard? currentGuard;
  final int redirectCount;  // For loop detection
}
```

---

## Route Build Context

**All route builders receive a `RouteBuildContext`**, not just params:

```dart
@immutable
class RouteBuildContext {
  /// Extracted path parameters (e.g., :userId → '123')
  final Map<String, String> params;

  /// Query parameters (e.g., ?tab=posts → {tab: 'posts'})
  final Map<String, String> query;

  /// Non-URL state passed via NavigateEvent.extra
  final Object? extra;

  /// The stack entry this build is for
  final StackEntry entry;

  /// Convenience: typed extra with fallback
  T? extraAs<T>() => extra is T ? extra as T : null;
}
```

This avoids breaking changes when you need query or extra in builders.

---

## Route Configuration

### RouteConfig

```dart
@immutable
class RouteConfig {
  /// Path pattern (e.g., '/profile/:id')
  final String path;

  /// Widget builder with full context
  final Widget Function(RouteBuildContext ctx) builder;

  /// Route title for display
  final String? title;

  /// Guards to run before entering
  final List<RouteGuard> guards;

  /// Nested child routes
  final List<RouteConfig> children;

  /// Scope name (optional) — each entry gets unique scopeId
  final String? scopeName;

  /// Default transition for this route
  final RouteTransition? transition;

  /// Custom page builder (for advanced Navigator 2.0 usage)
  final Page<dynamic> Function(Widget child, StackEntry entry)? pageBuilder;

  /// Whether this route should appear in history
  final bool trackInHistory;

  const RouteConfig({
    required this.path,
    required this.builder,
    this.title,
    this.guards = const [],
    this.children = const [],
    this.scopeName,
    this.transition,
    this.pageBuilder,
    this.trackInHistory = true,
  });
}
```

### RoutingConfig

```dart
@immutable
class RoutingConfig {
  /// All route configurations
  final List<RouteConfig> routes;

  /// Global guards (run for every navigation, before route guards)
  final List<RouteGuard> globalGuards;

  /// Route for unmatched paths
  final RouteConfig? notFoundRoute;

  /// Initial path on app start
  final String initialPath;

  /// Maximum history entries to keep
  final int maxHistoryLength;

  /// Maximum redirect chain length (default: 5)
  final int maxRedirects;

  /// Default transition
  final RouteTransition defaultTransition;

  /// Custom path parser (for advanced URL schemes)
  final RoutePath Function(String path)? pathParser;

  const RoutingConfig({
    required this.routes,
    this.globalGuards = const [],
    this.notFoundRoute,
    this.initialPath = '/',
    this.maxHistoryLength = 100,
    this.maxRedirects = 5,
    this.defaultTransition = RouteTransition.platform,
    this.pathParser,
  });
}
```

---

## Events

### Navigation Events

```dart
/// Navigate to a path
class NavigateEvent extends BlocEvent {
  final String path;
  final Object? extra;               // Non-URL state (any type)
  final bool replace;                // Replace current instead of push
  final RouteTransition? transition;
  final Duration? transitionDuration;
}

/// Pop the current route (no guards, immediate)
class PopEvent extends BlocEvent {
  final dynamic result;  // Return value to previous route
}

/// Pop until predicate matches (no guards)
class PopUntilEvent extends BlocEvent {
  final bool Function(StackEntry entry) predicate;
}

/// Pop to root (no guards)
class PopToRootEvent extends BlocEvent {}

/// Reset stack to single route (guards run on new root)
class ResetStackEvent extends BlocEvent {
  final String path;
  final Object? extra;
}

/// Handle deep link
class DeepLinkEvent extends BlocEvent {
  final Uri uri;
  final bool clearStack;  // Start fresh or maintain context
}
```

### Lifecycle Events

```dart
/// Initialize with configuration
class InitializeRoutingEvent extends BlocEvent {
  final RoutingConfig config;
}

/// Route became visible (emitted by RouterDelegate)
class RouteVisibleEvent extends BlocEvent {
  final String entryKey;
  final String path;
}

/// Route became hidden (emitted by RouterDelegate)
class RouteHiddenEvent extends BlocEvent {
  final String entryKey;
  final String path;
  final Duration timeVisible;
}
```

### Internal Events

```dart
/// Guard completed (internal)
class _GuardCompletedEvent extends BlocEvent {
  final RouteGuard guard;
  final GuardResult result;
}

/// All guards passed, commit navigation (internal)
class _CommitNavigationEvent extends BlocEvent {
  final StackEntry entry;
  final bool replace;
}
```

---

## Route Guards

### RouteGuard Interface

```dart
abstract class RouteGuard {
  /// Check if navigation should proceed
  ///
  /// [context] provides access to:
  /// - target path and params
  /// - current routing state
  /// - bloc scope for dependencies
  Future<GuardResult> check(RouteContext context);

  /// Priority for execution order (lower = first, default 0)
  int get priority => 0;
}

@immutable
class RouteContext {
  final String targetPath;
  final Map<String, String> params;
  final Map<String, String> query;
  final RoutingState currentState;
  final RouteConfig targetRoute;
}
```

### GuardResult

```dart
sealed class GuardResult {
  const GuardResult._();

  /// Allow navigation to proceed
  const factory GuardResult.allow() = AllowResult;

  /// Redirect to different path (does NOT preserve extra)
  const factory GuardResult.redirect(
    String path, {
    String? returnTo,
  }) = RedirectResult;

  /// Block navigation entirely (stay on current route)
  const factory GuardResult.block(String reason) = BlockResult;
}
```

### Built-in Guards

```dart
/// Requires authentication
class AuthGuard extends RouteGuard {
  final String loginPath;
  final bool Function() isAuthenticated;

  const AuthGuard({
    this.loginPath = '/login',
    required this.isAuthenticated,
  });

  @override
  Future<GuardResult> check(RouteContext context) async {
    if (isAuthenticated()) {
      return GuardResult.allow();
    }
    return GuardResult.redirect(loginPath, returnTo: context.targetPath);
  }
}

/// Requires specific permission
class PermissionGuard extends RouteGuard {
  final String permission;
  final bool Function(String) hasPermission;
  final String deniedPath;

  @override
  Future<GuardResult> check(RouteContext context) async {
    if (hasPermission(permission)) {
      return GuardResult.allow();
    }
    return GuardResult.block('Missing permission: $permission');
  }
}

/// Requires onboarding completion
class OnboardingGuard extends RouteGuard {
  final String onboardingPath;
  final bool Function() isOnboarded;

  @override
  Future<GuardResult> check(RouteContext context) async {
    if (isOnboarded()) {
      return GuardResult.allow();
    }
    return GuardResult.redirect(onboardingPath);
  }
}
```

---

## Transitions

### RouteTransition

```dart
enum RouteTransition {
  /// Platform default (Cupertino on iOS, Material on Android)
  platform,

  /// No animation
  none,

  /// Fade in/out
  fade,

  /// Slide from right
  slideRight,

  /// Slide from bottom
  slideBottom,

  /// Scale from center
  scale,

  /// Custom (provide pageBuilder)
  custom,
}
```

---

## Navigator 2.0 Integration

### JuiceRouterDelegate

```dart
class JuiceRouterDelegate extends RouterDelegate<RoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<RoutePath> {
  final RoutingBloc routingBloc;
  final GlobalKey<NavigatorState> navigatorKey;

  JuiceRouterDelegate({required this.routingBloc})
      : navigatorKey = GlobalKey<NavigatorState>() {
    // Listen to bloc changes
    routingBloc.stream.listen((_) => notifyListeners());
  }

  @override
  RoutePath? get currentConfiguration {
    final current = routingBloc.state.current;
    return current != null ? RoutePath(current.path, current.params) : null;
  }

  @override
  Future<void> setNewRoutePath(RoutePath configuration) async {
    routingBloc.send(DeepLinkEvent(uri: configuration.toUri()));
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      pages: routingBloc.state.stack.map(_buildPage).toList(),
      onPopPage: _handlePop,
      observers: [_VisibilityObserver(routingBloc)],  // For time-on-route
    );
  }

  bool _handlePop(Route<dynamic> route, dynamic result) {
    if (!route.didPop(result)) return false;
    routingBloc.send(PopEvent(result: result));
    return true;
  }
}

/// Observer that emits RouteVisible/HiddenEvent for time-on-route tracking
class _VisibilityObserver extends NavigatorObserver {
  final RoutingBloc routingBloc;
  final Map<Route, DateTime> _visibleSince = {};

  _VisibilityObserver(this.routingBloc);

  @override
  void didPush(Route route, Route? previousRoute) {
    _markVisible(route);
    if (previousRoute != null) _markHidden(previousRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _markHidden(route);
    if (previousRoute != null) _markVisible(previousRoute);
  }

  void _markVisible(Route route) {
    _visibleSince[route] = DateTime.now();
    // Emit RouteVisibleEvent...
  }

  void _markHidden(Route route) {
    final since = _visibleSince.remove(route);
    if (since != null) {
      final duration = DateTime.now().difference(since);
      // Emit RouteHiddenEvent with duration...
    }
  }
}
```

### JuiceRouteInformationParser

```dart
class JuiceRouteInformationParser extends RouteInformationParser<RoutePath> {
  final RoutingConfig config;

  JuiceRouteInformationParser({required this.config});

  @override
  Future<RoutePath> parseRouteInformation(RouteInformation info) async {
    final uri = Uri.parse(info.uri.toString());
    return RoutePath(uri.path, uri.queryParameters);
  }

  @override
  RouteInformation? restoreRouteInformation(RoutePath configuration) {
    return RouteInformation(uri: configuration.toUri());
  }
}
```

---

## Scope Integration

### How Scopes Work

Routes can declare a `scopeName`. When that route enters the stack:
1. A unique `scopeId` is generated for that `StackEntry`
2. `FeatureScope(scopeId)` is created (labeled with `scopeName`)
3. Blocs can register with this scope
4. `activeScopeIds` in state tracks current scopes

When that route leaves the stack:
1. `RoutingBloc` detects `scopeId` no longer in stack
2. Triggers `FeatureScope(scopeId).end()`
3. `ScopeLifecycleBloc` publishes `ScopeEndingNotification`
4. Feature blocs clean up

**Key:** Scope identity is by `scopeId` (unique per entry), not `scopeName`. Pushing `/checkout` twice creates two distinct scopes.

```dart
RouteConfig(
  path: '/checkout',
  scopeName: 'checkout',  // Label, not identity
  builder: (ctx) => CheckoutFlow(),
)

// Push twice:
// Entry 1: scopeId = 'checkout_abc123'
// Entry 2: scopeId = 'checkout_def456'
// Both are independent scopes
```

---

## Aviator vs RoutingBloc Guidelines

### The Two Layers

**Aviator** (core `juice`) and **RoutingBloc** (`juice_routing`) serve different purposes:

| Layer | Purpose | Knows About |
|-------|---------|-------------|
| **Aviator** | Express navigation **intent** | Logical names (`'showProfile'`, `'orderComplete'`) |
| **RoutingBloc** | Execute navigation **mechanics** | Paths (`'/profile/123'`), guards, stack, deep links |

**Key insight:** Aviator decouples *what* from *how*. RoutingBloc handles *how*.

### Why Both Exist

1. **Aviators work without juice_routing** — If you're not using this package, Aviators still let use cases trigger navigation without coupling to Navigator/routes.

2. **Intent abstraction** — A use case says `'orderComplete'`, not `'/orders/123/confirmation'`. The path is an implementation detail.

3. **Centralized mapping** — The intent→path translation lives in one place (`AviatorRoutingAdapter`), not scattered across use cases.

### When to Use What

| Scenario | Use | Why |
|----------|-----|-----|
| **Use case completes, needs to navigate** | Aviator | Business logic shouldn't know paths |
| **Widget button triggers navigation** | Either | RoutingBloc direct is simpler; Aviator if you want decoupling |
| **Deep link arrives** | RoutingBloc | It's already a path |
| **Back button / pop** | RoutingBloc | Stack operation, no business intent |
| **Query "where am I?"** | RoutingBloc state | Observable navigation state |
| **App doesn't use juice_routing** | Aviator only | Aviator handles the full navigation |

### Guards Can Reject Aviator Navigation

**Important:** An Aviator intent is not guaranteed to succeed.

When `AviatorRoutingAdapter` converts intent to `NavigateEvent`, that event goes through the guard pipeline. Guards can block or redirect.

```dart
// Use case triggers intent
emitUpdate(aviatorName: 'adminPanel', aviatorArgs: {});

// Adapter converts to path
// → NavigateEvent(path: '/admin')

// AdminGuard checks permissions
// → GuardResult.block('Not an admin')

// Navigation does NOT happen
// RoutingState.lastError = GuardBlockedError
```

**This is correct behavior.** The use case expresses intent; the routing layer enforces rules. A use case may not meet all criteria (auth, permissions, onboarding).

### Architecture Patterns

#### Pattern 1: No juice_routing (Aviators Only)

For simpler apps that don't need guards, deep links, or observable navigation state:

```dart
// Use case
emitUpdate(aviatorName: 'profile', aviatorArgs: {'userId': id});

// Aviator handles navigation directly
class ProfileAviator extends AviatorBase {
  final BuildContext context;

  @override
  void navigate(String name, Map<String, dynamic> args) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ProfileScreen(userId: args['userId']),
    ));
  }
}
```

#### Pattern 2: juice_routing with Aviators (Recommended for Complex Apps)

Use cases express intent, adapter bridges to RoutingBloc:

```dart
// Use case (doesn't know paths)
emitUpdate(aviatorName: 'orderComplete', aviatorArgs: {'orderId': order.id});

// Centralized adapter configuration
final aviator = AviatorRoutingAdapter(
  routingBloc: routingBloc,
  pathBuilder: (name, args) => switch (name) {
    'orderComplete' => '/orders/${args['orderId']}/confirmation',
    'showProfile' => '/profile/${args['userId']}',
    'checkout' => '/checkout',
    _ => '/$name',
  },
);

// Widget can also use Aviator for decoupling
ElevatedButton(
  onPressed: () => aviator.navigate('showProfile', {'userId': '123'}),
  child: Text('View Profile'),
)

// Or use RoutingBloc directly when path is obvious
IconButton(
  onPressed: () => routingBloc.send(NavigateEvent(path: '/settings')),
  icon: Icon(Icons.settings),
)
```

#### Pattern 3: juice_routing Only (No Aviators)

If your use cases don't trigger navigation—only widgets do—skip Aviators:

```dart
// Widgets navigate directly
ElevatedButton(
  onPressed: () => routingBloc.send(NavigateEvent(
    path: '/profile/123',
    extra: ProfileExtra(source: 'home'),
  )),
  child: Text('View Profile'),
)
```

### Decision Flowchart

```
Do your use cases trigger navigation?
│
├─ NO → Use RoutingBloc directly from widgets (Pattern 3)
│
└─ YES → Do you want use cases decoupled from paths?
         │
         ├─ NO → Use cases send NavigateEvent directly
         │
         └─ YES → Use Aviators + AviatorRoutingAdapter (Pattern 2)
                  │
                  └─ Do you need guards/deep links/observable state?
                     │
                     ├─ NO → Aviators only, no juice_routing (Pattern 1)
                     │
                     └─ YES → Aviators + juice_routing (Pattern 2)
```

### AviatorRoutingAdapter

The bridge between intent and execution:

```dart
/// Adapter that connects Juice Aviators to RoutingBloc
class AviatorRoutingAdapter extends AviatorBase {
  final RoutingBloc routingBloc;

  /// Maps intent name + args to a path
  final String Function(String name, Map<String, dynamic> args) pathBuilder;

  /// Optional: extract extra from args (default: pass args as extra)
  final Object? Function(String name, Map<String, dynamic> args)? extraBuilder;

  AviatorRoutingAdapter({
    required this.routingBloc,
    required this.pathBuilder,
    this.extraBuilder,
  });

  @override
  FutureOr<void> navigate(String name, Map<String, dynamic> args) {
    final path = pathBuilder(name, args);
    final extra = extraBuilder?.call(name, args) ?? args;
    routingBloc.send(NavigateEvent(path: path, extra: extra));
  }
}
```

### Summary

| Principle | Guideline |
|-----------|-----------|
| **Aviator = intent** | Use cases express *what* should happen |
| **RoutingBloc = execution** | Routing layer handles *how* it happens |
| **Guards apply to both** | Aviator intent → NavigateEvent → guards can reject |
| **Mapping is centralized** | `pathBuilder` in adapter, not scattered |
| **Widgets can use either** | Direct RoutingBloc for simple cases, Aviator for decoupling |
| **Aviators work standalone** | juice_routing is optional; Aviators still useful without it |

---

## Rebuild Groups

| Group | Updates When |
|-------|--------------|
| `routing:stack` | Stack changes (push, pop, replace) |
| `routing:current` | Current route changes |
| `routing:pending` | Navigation in progress (guards running) |
| `routing:history` | History entry added |
| `routing:error` | Navigation error occurred |

---

## Error Handling

### RoutingError Hierarchy

```dart
sealed class RoutingError implements Exception {
  String get message;
}

/// No route matches path
class RouteNotFoundError extends RoutingError {
  final String path;
  @override
  String get message => 'No route found for: $path';
}

/// Guard blocked navigation
class GuardBlockedError extends RoutingError {
  final String path;
  final String reason;
  @override
  String get message => 'Navigation to $path blocked: $reason';
}

/// Guard threw exception
class GuardExceptionError extends RoutingError {
  final String path;
  final RouteGuard guard;
  final Object exception;
  final StackTrace? stackTrace;
  @override
  String get message => 'Guard ${guard.runtimeType} threw: $exception';
}

/// Redirect loop detected
class RedirectLoopError extends RoutingError {
  final List<String> chain;
  @override
  String get message => 'Redirect loop detected: ${chain.join(' → ')}';
}

/// Invalid path format
class InvalidPathError extends RoutingError {
  final String path;
  @override
  String get message => 'Invalid path format: $path';
}

/// Cannot pop (at root)
class CannotPopError extends RoutingError {
  @override
  String get message => 'Cannot pop: already at root';
}
```

---

## Testing

### BlocTester Integration

```dart
test('navigates to profile with auth guard', () async {
  final tester = BlocTester<RoutingBloc, RoutingState>(
    bloc: RoutingBloc(config: testConfig),
  );

  // Setup: user is authenticated
  authBloc.emit(AuthState(isAuthenticated: true));

  // Act
  await tester.send(NavigateEvent(path: '/profile/123'));

  // Assert
  tester.expectState((state) {
    expect(state.currentPath, '/profile/123');
    expect(state.currentParams, {'userId': '123'});
    expect(state.stack.length, 2); // home + profile
  });
});

test('auth guard redirects to login', () async {
  final tester = BlocTester<RoutingBloc, RoutingState>(
    bloc: RoutingBloc(config: testConfig),
  );

  // Setup: user is NOT authenticated
  authBloc.emit(AuthState(isAuthenticated: false));

  // Act
  await tester.send(NavigateEvent(path: '/profile/123'));

  // Assert
  tester.expectState((state) {
    expect(state.currentPath, '/login');
    expect(state.current?.query['returnTo'], '/profile/123');
  });
});

test('redirect loop is capped', () async {
  // Guard A redirects to /b, Guard B redirects to /a
  final tester = BlocTester<RoutingBloc, RoutingState>(
    bloc: RoutingBloc(config: loopConfig),
  );

  await tester.send(NavigateEvent(path: '/a'));

  tester.expectState((state) {
    expect(state.lastError, isA<RedirectLoopError>());
    expect(state.currentPath, '/'); // Unchanged
  });
});
```

---

## Implementation Phases

### Phase 1: Core MVP

1. **PathResolver**
   - Match `/users/:id` patterns
   - Support nested children
   - Parse query parameters
   - Return `(RouteConfig, params, query)` or not-found

2. **Stack core**
   - Push / replace / pop / reset
   - Generate unique `StackEntry.key`
   - Maintain stack as immutable list

3. **Guards pipeline**
   - Global guards + route guards
   - Priority ordering
   - Redirect + block + allow
   - Redirect loop cap (5)
   - Guard exception handling

4. **Navigator 2.0**
   - `JuiceRouterDelegate` renders `state.stack → pages`
   - `JuiceRouteInformationParser` (basic)
   - `_VisibilityObserver` for time-on-route

5. **Rebuild groups**
   - `routing:stack`, `routing:current`, `routing:pending`, `routing:error`

**Phase 1 does NOT include:**
- Scope integration (Phase 2)
- Deep link handling beyond basic parser (Phase 2)
- History persistence (Phase 3)
- Nested navigation helpers (Phase 3)

### Phase 2: Polish

- [ ] Deep link handling (cold/warm start)
- [ ] Scope integration with `ScopeLifecycleBloc`
- [ ] Route transitions
- [ ] History tracking with time-on-route
- [ ] `AviatorRoutingAdapter`

### Phase 3: Advanced

- [ ] Nested navigation (`RoutingBloc` per navigator)
- [ ] Route/history persistence via `juice_storage`
- [ ] Analytics helpers
- [ ] Shell routes

---

## Open Questions

1. **Return values**: Best pattern for `await routingBloc.navigate().result`? (Completer per navigation?)
2. **Web URLs**: Hash vs path-based routing for web? (Probably config option)
3. **Preloading**: Should guards be able to preload data before transition completes?
4. **Hero transitions**: How should shared element animations coordinate?

---

## Summary of Contract Guarantees

| Guarantee | Behavior |
|-----------|----------|
| **Atomicity** | Navigation either commits fully or not at all |
| **Concurrency** | One pending navigation; new ones queue (depth 1, latest wins) |
| **Redirect cap** | Max 5 redirects before `RedirectLoopError` |
| **Guard errors** | Exception → `GuardExceptionError`, navigation aborted |
| **Pop behavior** | Pop events bypass guards, execute immediately |
| **Scope identity** | By `scopeId` (unique per entry), not `scopeName` |
| **One bloc per navigator** | Nested navigators get their own `RoutingBloc` |
