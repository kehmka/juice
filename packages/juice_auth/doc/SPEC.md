# juice_auth Specification

> **Status:** Implemented (shipping). This document is the original design
> contract. Where the implementation and this spec differ, **the code is the
> source of truth** — see [Implementation Notes](#implementation-notes) for the
> known, intentional divergences.
> **Package:** `juice_auth`
> **Primary Bloc:** `AuthBloc`

## Overview

**juice_auth** provides a foundation bloc for authentication lifecycle management. While `juice_network` solves "how do I make authenticated requests?" and `juice_routing` solves "how do I protect routes?", AuthBloc solves "who is the user, and what is their session state?"

It owns the authentication lifecycle: credentials in → session state out. Token storage, refresh, multi-provider login, biometric unlock, and session expiry—all in one bloc with deterministic state transitions.

---

## Dependencies

| Package | Dependency | Purpose |
|---------|------------|---------|
| `juice` | Required | Core bloc infrastructure, BlocScope |
| `juice_storage` | Required | Secure token persistence via `StorageBloc` |
| `juice_network` | Optional | Token refresh via HTTP, `AuthInterceptor` integration |
| `juice_routing` | Optional | Route guard callbacks, post-login redirect |

**Registration order:**

```dart
void main() {
  // 1. StorageBloc (token persistence)
  BlocScope.register<StorageBloc>(
    () => StorageBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  // 2. AuthBloc (reads tokens from storage on init)
  BlocScope.register<AuthBloc>(
    () => AuthBloc(config: authConfig),
    lifecycle: BlocLifecycle.permanent,
  );

  // 3. FetchBloc (uses AuthBloc for identity + tokens)
  BlocScope.register<FetchBloc>(
    () => FetchBloc(
      authIdentityProvider: () => BlocScope.get<AuthBloc>().state.userId,
    ),
    lifecycle: BlocLifecycle.permanent,
  );

  // 4. RoutingBloc (uses AuthBloc for guard callbacks)
  BlocScope.register<RoutingBloc>(
    () => RoutingBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(MyApp());
}
```

---

## Why Use AuthBloc?

> **Firebase Auth is a provider. AuthBloc is a session contract.**
>
> It makes auth state reactive, token refresh automatic, multi-provider composable, session expiry observable, and the entire lifecycle testable—without coupling your app to any auth backend.

---

### The 6 Problems With "Just Auth Provider"

Every team without an auth foundation ends up with:

```dart
// Scattered across your codebase:
class LoginScreen extends StatefulWidget {
  void _login() async {
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email, password: _password,
      );
      // Store token... somewhere
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', cred.credential?.token ?? '');
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      setState(() => _error = e.toString()); // String soup
    }
  }
}

class ApiService {
  Future<String?> _getToken() async {
    // Hope this is the same logic as LoginScreen...
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }
}

class ProfileScreen extends StatefulWidget {
  void _logout() async {
    await FirebaseAuth.instance.signOut();
    // Clear storage... maybe?
    // Cancel pending requests... probably not
    // Navigate to login... hope nobody forgot
  }
}
```

**This creates real bugs:**

| # | Problem | What Goes Wrong |
|---|---------|-----------------|
| 1 | **Token scattered** | Token in SharedPrefs, Firebase, memory—which is current? Race conditions on refresh |
| 2 | **Session state invisible** | "Is the user logged in?" requires async check, different per screen |
| 3 | **Refresh chaos** | 5 concurrent 401s → 5 refresh attempts → 4 fail → logout storm |
| 4 | **Logout incomplete** | Sign out but tokens linger in storage, cache still has user data |
| 5 | **Provider lock-in** | Firebase calls in 40 files. Switch to Supabase? Rewrite everything |
| 6 | **Untestable** | Can't unit test "session expires → redirect to login" without real auth |

### The 6 Things AuthBloc Adds

| # | Capability | What It Does |
|---|------------|--------------|
| 1 | **Single source of truth** | `authBloc.state.isAuthenticated` — synchronous, reactive, one place |
| 2 | **Automatic token lifecycle** | Secure storage, silent refresh, expiry detection — zero widget code |
| 3 | **Provider abstraction** | `AuthProvider` interface — swap Firebase/Supabase/custom without touching UI |
| 4 | **Atomic logout** | One event clears tokens, storage, cache, and navigates — nothing leaks |
| 5 | **Session observability** | Expiry countdown, refresh status, provider info — all in `AuthState` |
| 6 | **Testable lifecycle** | Mock `AuthProvider`, send events, assert state — no auth backend needed |

```dart
// One place, consistent behavior:
authBloc.send(LoginEvent(
  provider: EmailAuthProvider(
    email: 'user@example.com',
    password: 'secret',
  ),
));

// State updates reactively:
// authBloc.state.isAuthenticated → true
// authBloc.state.user → User(email: ...)
// authBloc.state.session → Session(expiresAt: ..., provider: 'email')
```

**And in your UI:**

```dart
class ProfileWidget extends StatelessJuiceWidget<AuthBloc> {
  ProfileWidget({super.key}) : super(groups: {AuthGroups.user});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    if (!bloc.state.isAuthenticated) {
      return LoginPrompt();
    }
    return Text('Hello, ${bloc.state.user!.displayName}');
  }
}
```

### Side-by-Side Comparison

| Concern | Just Provider SDK | AuthBloc |
|---------|-------------------|----------|
| **Login** | `firebase.signIn()` in each screen | `LoginEvent` with `AuthProvider` |
| **"Am I logged in?"** | `await firebase.currentUser` (async!) | `authBloc.state.isAuthenticated` (sync) |
| **Token storage** | DIY SharedPreferences | Automatic secure storage |
| **Token refresh** | Manual interceptor, hope it works | Singleflight refresh, observable |
| **Logout** | Sign out + clear storage + navigate | One `LogoutEvent`, atomic cleanup |
| **Session expiry** | Timer somewhere, maybe | `session.expiresAt` + auto-refresh |
| **Swap providers** | Rewrite 40 files | Swap `AuthProvider`, zero UI changes |
| **Testing** | Mock Firebase (good luck) | Mock `AuthProvider`, assert `AuthState` |
| **Multi-account** | DIY everything | Built-in account switching |

### Who Should Use AuthBloc?

| If you... | Use AuthBloc? |
|-----------|---------------|
| Have a login screen | **Yes** |
| Store tokens | **Yes** |
| Need token refresh | **Yes** |
| Have protected routes | **Yes** |
| Use multiple auth providers | **Yes** |
| Want testable auth logic | **Yes** |
| Building a "real" app | **Yes** |

### Who Shouldn't?

- Apps with no authentication
- Prototypes with hardcoded users
- Backend-only Dart packages

---

## Foundation Contract

AuthBloc guarantees these behaviors:

### A. Single Source of Truth

**`authBloc.state.isAuthenticated` is always synchronous and current.**

No async checks. No stale values. The bloc owns session state. Widgets, guards, interceptors, and use cases all read from one place.

### B. Atomic Login

**A `LoginEvent` either transitions to `authenticated` or remains `unauthenticated`.**

There are no partial states. If the provider call succeeds but token storage fails, the login is rolled back and `AuthError` is emitted. The user never sees a half-logged-in state.

### C. Atomic Logout

**A `LogoutEvent` clears all session artifacts in a deterministic order:**

1. Revoke tokens with provider (best-effort, non-blocking)
2. Clear secure storage (tokens)
3. Clear cached user data
4. Reset state to `unauthenticated`
5. Emit `auth:status` rebuild group

No tokens linger. No stale cache. No orphaned sessions.

### D. Singleflight Token Refresh

**If N components trigger a token refresh simultaneously, only 1 refresh executes.**

All N callers await the same `Completer`. This prevents the "401 storm" where concurrent refresh attempts invalidate each other.

### E. Session Expiry Detection

**AuthBloc proactively detects token expiry.**

- If `expiresAt` is known, a timer fires before expiry to trigger silent refresh
- If refresh fails, state transitions to `sessionExpired` (not `unauthenticated`)
- `sessionExpired` lets UI show "session expired" vs "not logged in" — different UX

### F. Provider Abstraction

**Auth providers implement a simple interface. AuthBloc doesn't know about Firebase, Supabase, or OAuth.**

Providers are injected, not imported. Swap providers without touching AuthBloc, UI, or guards.

### G. Credential Isolation

**AuthBloc never exposes raw credentials (passwords, OAuth secrets) in state.**

- `AuthState` contains tokens (access, refresh) and user metadata
- Passwords are passed through `AuthProvider` and never stored
- Tokens are stored in secure storage, not in-memory state (state holds references)

---

## State Model

### AuthState

```dart
@immutable
class AuthState extends BlocState {
  /// Current authentication status
  final AuthStatus status;

  /// Authenticated user (null when unauthenticated)
  final AuthUser? user;

  /// Active session (null when unauthenticated)
  final AuthSession? session;

  /// Last auth error (cleared on next successful operation)
  final AuthError? lastError;

  /// Whether a token refresh is currently in progress
  final bool isRefreshing;

  /// Pending login provider (during login flow)
  final String? pendingProvider;

  // Convenience getters
  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isSessionExpired => status == AuthStatus.sessionExpired;
  String? get userId => user?.id;
  String? get accessToken => session?.accessToken;
  bool get hasRole(String role) => user?.roles.contains(role) ?? false;

  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.user,
    this.session,
    this.lastError,
    this.isRefreshing = false,
    this.pendingProvider,
  });

  AuthState copyWith({...});
}
```

### AuthStatus

```dart
enum AuthStatus {
  /// Initial state, before restore attempt
  unknown,

  /// No active session
  unauthenticated,

  /// Active, valid session
  authenticated,

  /// Session existed but expired (distinct from unauthenticated for UX)
  sessionExpired,
}
```

**Why `unknown`?** On app start, we don't know if there's a stored session until `RestoreSessionUseCase` runs. UI can show a splash screen while `status == unknown`.

**Why `sessionExpired`?** "Your session expired, please sign in again" is a different UX from "Welcome, please sign in." The status distinction enables this without boolean flags.

### AuthUser

```dart
@immutable
class AuthUser {
  /// Unique user identifier
  final String id;

  /// Display name
  final String? displayName;

  /// Email address
  final String? email;

  /// Profile photo URL
  final String? photoUrl;

  /// User roles (for RoleGuard integration)
  final Set<String> roles;

  /// Provider-specific metadata (Firebase UID, OAuth claims, etc.)
  final Map<String, dynamic> metadata;

  const AuthUser({
    required this.id,
    this.displayName,
    this.email,
    this.photoUrl,
    this.roles = const {},
    this.metadata = const {},
  });

  AuthUser copyWith({...});
}
```

### AuthSession

```dart
@immutable
class AuthSession {
  /// Access token for API calls
  final String accessToken;

  /// Refresh token (null if provider doesn't support refresh)
  final String? refreshToken;

  /// When the access token expires (null if unknown)
  final DateTime? expiresAt;

  /// Which provider created this session
  final String providerName;

  /// When the session was created
  final DateTime createdAt;

  /// When the token was last refreshed
  final DateTime? lastRefreshedAt;

  // Convenience getters
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  Duration? get timeUntilExpiry =>
      expiresAt != null ? expiresAt!.difference(DateTime.now()) : null;

  const AuthSession({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    required this.providerName,
    required this.createdAt,
    this.lastRefreshedAt,
  });

  AuthSession copyWith({...});
}
```

---

## Auth Provider Interface

### AuthProvider

```dart
/// Contract that any auth backend must implement.
/// AuthBloc delegates all provider-specific logic to this interface.
abstract class AuthProvider {
  /// Human-readable provider name (e.g., 'email', 'google', 'apple')
  String get name;

  /// Authenticate with provider-specific credentials.
  /// Returns [AuthResult] with tokens and user info.
  /// Throws [AuthProviderException] on failure.
  Future<AuthResult> authenticate(AuthCredentials credentials);

  /// Refresh the access token using the refresh token.
  /// Returns new [AuthResult] with updated tokens.
  /// Throws [AuthProviderException] if refresh fails (session invalid).
  Future<AuthResult> refreshToken(String refreshToken);

  /// Revoke the session (best-effort, for logout).
  /// Should not throw — failures are logged, not propagated.
  Future<void> revokeSession(AuthSession session);

  /// Fetch fresh user profile from provider.
  /// Used for periodic profile sync (optional).
  Future<AuthUser?> fetchUser(String accessToken) async => null;

  /// Whether this provider supports token refresh
  bool get supportsRefresh => true;

  /// Dispose provider resources
  Future<void> dispose() async {}
}
```

### AuthCredentials

```dart
/// Base class for provider-specific credentials.
/// Each provider defines its own credential type.
abstract class AuthCredentials {
  const AuthCredentials();
}

/// Email + password credentials
class EmailCredentials extends AuthCredentials {
  final String email;
  final String password;
  const EmailCredentials({required this.email, required this.password});
}

/// OAuth credentials (from platform OAuth flow)
class OAuthCredentials extends AuthCredentials {
  final String provider; // 'google', 'apple', 'github'
  final String idToken;
  final String? accessToken;
  const OAuthCredentials({
    required this.provider,
    required this.idToken,
    this.accessToken,
  });
}

/// API key credentials (for service-to-service)
class ApiKeyCredentials extends AuthCredentials {
  final String apiKey;
  const ApiKeyCredentials({required this.apiKey});
}

/// Biometric unlock credentials (re-auth with stored token)
class BiometricCredentials extends AuthCredentials {
  final String storedRefreshToken;
  const BiometricCredentials({required this.storedRefreshToken});
}
```

### AuthResult

```dart
/// Returned by AuthProvider after successful authentication or refresh.
@immutable
class AuthResult {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final AuthUser user;

  const AuthResult({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    required this.user,
  });
}
```

---

## Auth Configuration

### AuthConfig

```dart
@immutable
class AuthConfig {
  /// Registered auth providers (at least one required)
  final Map<String, AuthProvider> providers;

  /// Refresh buffer — trigger refresh this long before expiry
  /// Default: 60 seconds before token expires
  final Duration refreshBuffer;

  /// Whether to attempt session restore on initialization
  /// Default: true
  final bool restoreSessionOnInit;

  /// Secure storage key prefix (for multi-app isolation)
  /// Default: 'juice_auth'
  final String storagePrefix;

  /// Maximum login attempts before cooldown
  /// Default: 5
  final int maxLoginAttempts;

  /// Cooldown duration after max login attempts
  /// Default: 30 seconds
  final Duration loginCooldown;

  /// Whether to persist the refresh token to secure storage
  /// Default: true
  final bool persistRefreshToken;

  /// Token storage keys
  String get accessTokenKey => '${storagePrefix}_access_token';
  String get refreshTokenKey => '${storagePrefix}_refresh_token';
  String get sessionKey => '${storagePrefix}_session';
  String get userKey => '${storagePrefix}_user';

  const AuthConfig({
    required this.providers,
    this.refreshBuffer = const Duration(seconds: 60),
    this.restoreSessionOnInit = true,
    this.storagePrefix = 'juice_auth',
    this.maxLoginAttempts = 5,
    this.loginCooldown = const Duration(seconds: 30),
    this.persistRefreshToken = true,
  });
}
```

---

## Events

### Command Events

```dart
/// Initialize AuthBloc with configuration.
/// Triggers session restore if configured.
class InitializeAuthEvent extends EventBase {
  final AuthConfig config;
  InitializeAuthEvent({required this.config});
}

/// Login with a specific provider and credentials.
class LoginEvent extends EventBase {
  final String providerName;
  final AuthCredentials credentials;
  LoginEvent({required this.providerName, required this.credentials});
}

/// Logout and clear all session data.
class LogoutEvent extends EventBase {
  /// If true, skip provider revocation (for forced logout on refresh failure)
  final bool force;
  LogoutEvent({this.force = false});
}

/// Manually trigger a token refresh.
/// Usually not needed — AuthBloc refreshes proactively.
class RefreshTokenEvent extends EventBase {}

/// Update user profile in state (after profile edit, etc.)
class UpdateUserEvent extends EventBase {
  final AuthUser updatedUser;
  UpdateUserEvent({required this.updatedUser});
}

/// Switch to a different stored account (multi-account support)
class SwitchAccountEvent extends EventBase {
  final String userId;
  SwitchAccountEvent({required this.userId});
}
```

### Internal Events

```dart
/// Emitted when the refresh timer fires (before token expiry).
/// Not dispatched by user code.
class _TokenExpiryEvent extends EventBase {}

/// Emitted after session restore completes (success or failure).
class _SessionRestoredEvent extends EventBase {
  final AuthResult? result;
  final String? providerName;
  _SessionRestoredEvent({this.result, this.providerName});
}
```

---

## Use Cases

### LoginUseCase

```dart
class LoginUseCase extends BlocUseCase<AuthBloc, LoginEvent> {
  @override
  Future<void> execute(LoginEvent event) async {
    // 1. Rate limit check
    if (bloc.state._loginAttempts >= bloc.config.maxLoginAttempts) {
      emitFailure(error: AuthError.rateLimited(bloc.config.loginCooldown));
      return;
    }

    // 2. Resolve provider
    final provider = bloc.config.providers[event.providerName];
    if (provider == null) {
      emitFailure(error: AuthError.unknownProvider(event.providerName));
      return;
    }

    // 3. Show loading
    emitWaiting();
    emitUpdate(
      newState: bloc.state.copyWith(pendingProvider: event.providerName),
      groupsToRebuild: {AuthGroups.status},
    );

    try {
      // 4. Authenticate
      final result = await provider.authenticate(event.credentials);

      // 5. Persist tokens to secure storage
      await _persistTokens(result);

      // 6. Start refresh timer
      bloc._scheduleRefresh(result.expiresAt);

      // 7. Commit state
      emitUpdate(
        newState: AuthState(
          status: AuthStatus.authenticated,
          user: result.user,
          session: AuthSession(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: result.expiresAt,
            providerName: event.providerName,
            createdAt: DateTime.now(),
          ),
        ),
        groupsToRebuild: {AuthGroups.status, AuthGroups.user, AuthGroups.session},
        aviatorName: 'loginSuccess',
        aviatorArgs: {'userId': result.user.id},
      );
    } on AuthProviderException catch (e, st) {
      emitFailure(
        error: AuthError.providerError(e.message, providerName: event.providerName),
        errorStackTrace: st,
      );
      emitUpdate(
        newState: bloc.state.copyWith(pendingProvider: null),
        groupsToRebuild: {AuthGroups.error},
      );
    }
  }
}
```

### LogoutUseCase

```dart
class LogoutUseCase extends BlocUseCase<AuthBloc, LogoutEvent> {
  @override
  Future<void> execute(LogoutEvent event) async {
    final session = bloc.state.session;

    // 1. Cancel refresh timer
    bloc._cancelRefreshTimer();

    // 2. Revoke with provider (best-effort)
    if (!event.force && session != null) {
      final provider = bloc.config.providers[session.providerName];
      try {
        await provider?.revokeSession(session);
      } catch (_) {
        // Best-effort — don't block logout on revocation failure
      }
    }

    // 3. Clear secure storage
    await _clearStoredTokens();

    // 4. Reset state
    emitUpdate(
      newState: const AuthState(status: AuthStatus.unauthenticated),
      groupsToRebuild: {AuthGroups.status, AuthGroups.user, AuthGroups.session},
      aviatorName: 'logoutComplete',
    );
  }
}
```

### RefreshTokenUseCase

```dart
class RefreshTokenUseCase extends BlocUseCase<AuthBloc, RefreshTokenEvent> {
  /// Singleflight completer — prevents concurrent refresh attempts
  static Completer<String?>? _refreshInFlight;

  @override
  Future<void> execute(RefreshTokenEvent event) async {
    final session = bloc.state.session;
    if (session?.refreshToken == null) {
      emitFailure(error: AuthError.noRefreshToken());
      return;
    }

    // Singleflight: if refresh already in progress, await it
    if (_refreshInFlight != null) {
      await _refreshInFlight!.future;
      return;
    }

    _refreshInFlight = Completer<String?>();

    try {
      emitUpdate(
        newState: bloc.state.copyWith(isRefreshing: true),
        groupsToRebuild: {AuthGroups.session},
      );

      final provider = bloc.config.providers[session!.providerName]!;
      final result = await provider.refreshToken(session.refreshToken!);

      // Persist new tokens
      await _persistTokens(result);

      // Reschedule refresh timer
      bloc._scheduleRefresh(result.expiresAt);

      final newSession = session.copyWith(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken ?? session.refreshToken,
        expiresAt: result.expiresAt,
        lastRefreshedAt: DateTime.now(),
      );

      _refreshInFlight!.complete(result.accessToken);

      emitUpdate(
        newState: bloc.state.copyWith(
          session: newSession,
          user: result.user,
          isRefreshing: false,
        ),
        groupsToRebuild: {AuthGroups.session},
      );
    } catch (e, st) {
      _refreshInFlight!.completeError(e);

      // Refresh failed → session expired (not unauthenticated)
      emitUpdate(
        newState: bloc.state.copyWith(
          status: AuthStatus.sessionExpired,
          isRefreshing: false,
        ),
        groupsToRebuild: {AuthGroups.status, AuthGroups.session},
      );

      emitFailure(error: AuthError.refreshFailed(e.toString()), errorStackTrace: st);
    } finally {
      _refreshInFlight = null;
    }
  }
}
```

### RestoreSessionUseCase

```dart
class RestoreSessionUseCase extends BlocUseCase<AuthBloc, InitializeAuthEvent> {
  @override
  Future<void> execute(InitializeAuthEvent event) async {
    if (!event.config.restoreSessionOnInit) {
      emitUpdate(
        newState: const AuthState(status: AuthStatus.unauthenticated),
        groupsToRebuild: {AuthGroups.status},
      );
      return;
    }

    try {
      // 1. Read stored tokens from secure storage
      final storedSession = await _readStoredSession();
      if (storedSession == null) {
        emitUpdate(
          newState: const AuthState(status: AuthStatus.unauthenticated),
          groupsToRebuild: {AuthGroups.status},
        );
        return;
      }

      // 2. Check if refresh token is still valid
      final provider = event.config.providers[storedSession.providerName];
      if (provider == null || storedSession.refreshToken == null) {
        await _clearStoredTokens();
        emitUpdate(
          newState: const AuthState(status: AuthStatus.unauthenticated),
          groupsToRebuild: {AuthGroups.status},
        );
        return;
      }

      // 3. Refresh to get a fresh access token
      final result = await provider.refreshToken(storedSession.refreshToken!);

      // 4. Persist new tokens
      await _persistTokens(result);

      // 5. Schedule refresh timer
      bloc._scheduleRefresh(result.expiresAt);

      // 6. Commit authenticated state
      emitUpdate(
        newState: AuthState(
          status: AuthStatus.authenticated,
          user: result.user,
          session: AuthSession(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: result.expiresAt,
            providerName: storedSession.providerName,
            createdAt: DateTime.now(),
            lastRefreshedAt: DateTime.now(),
          ),
        ),
        groupsToRebuild: {AuthGroups.status, AuthGroups.user, AuthGroups.session},
      );
    } catch (e) {
      // Restore failed — go to unauthenticated, not error
      await _clearStoredTokens();
      emitUpdate(
        newState: const AuthState(status: AuthStatus.unauthenticated),
        groupsToRebuild: {AuthGroups.status},
      );
    }
  }
}
```

### UpdateUserUseCase

```dart
class UpdateUserUseCase extends BlocUseCase<AuthBloc, UpdateUserEvent> {
  @override
  Future<void> execute(UpdateUserEvent event) async {
    if (!bloc.state.isAuthenticated) return;

    emitUpdate(
      newState: bloc.state.copyWith(user: event.updatedUser),
      groupsToRebuild: {AuthGroups.user},
    );
  }
}
```

---

## Rebuild Groups

```dart
abstract class AuthGroups {
  /// Auth status changed (login, logout, session expiry)
  static const status = 'auth:status';

  /// User profile changed
  static const user = 'auth:user';

  /// Session updated (token refresh, expiry change)
  static const session = 'auth:session';

  /// Auth error occurred
  static const error = 'auth:error';
}
```

**Usage in widgets:**

```dart
// Only rebuild when auth status changes (login/logout)
class AuthGate extends StatelessJuiceWidget<AuthBloc> {
  AuthGate({super.key}) : super(groups: {AuthGroups.status});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    switch (bloc.state.status) {
      case AuthStatus.unknown:
        return SplashScreen();
      case AuthStatus.unauthenticated:
        return LoginScreen();
      case AuthStatus.authenticated:
        return HomeScreen();
      case AuthStatus.sessionExpired:
        return SessionExpiredScreen();
    }
  }
}

// Only rebuild when user profile changes
class UserAvatar extends StatelessJuiceWidget<AuthBloc> {
  UserAvatar({super.key}) : super(groups: {AuthGroups.user});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final user = bloc.state.user;
    if (user?.photoUrl != null) {
      return CircleAvatar(backgroundImage: NetworkImage(user!.photoUrl!));
    }
    return CircleAvatar(child: Icon(Icons.person));
  }
}
```

---

## Aviators

```dart
AuthBloc() : super(const AuthState()) {
  registerAviators([
    Aviator(
      name: 'loginSuccess',
      navigateWhere: (args) {
        final routingBloc = BlocScope.get<RoutingBloc>();
        // Navigate to home or return-to URL
        final returnTo = args['returnTo'] as String?;
        routingBloc.navigate(returnTo ?? '/');
      },
    ),
    Aviator(
      name: 'logoutComplete',
      navigateWhere: (args) {
        final routingBloc = BlocScope.get<RoutingBloc>();
        routingBloc.resetStack('/login');
      },
    ),
    Aviator(
      name: 'sessionExpired',
      navigateWhere: (args) {
        final routingBloc = BlocScope.get<RoutingBloc>();
        routingBloc.navigate('/login', replace: true);
      },
    ),
  ]);
}
```

---

## Integration Points

### With juice_routing (Guards)

AuthBloc provides callbacks — it does not depend on juice_routing:

```dart
// In route configuration:
final routes = RoutingConfig(
  routes: [
    RouteConfig(
      path: '/profile',
      builder: (ctx) => ProfileScreen(),
      guards: [
        AuthGuard(
          isAuthenticated: () => BlocScope.get<AuthBloc>().state.isAuthenticated,
        ),
      ],
    ),
    RouteConfig(
      path: '/login',
      builder: (ctx) => LoginScreen(),
      guards: [
        GuestGuard(
          isAuthenticated: () => BlocScope.get<AuthBloc>().state.isAuthenticated,
        ),
      ],
    ),
    RouteConfig(
      path: '/admin',
      builder: (ctx) => AdminScreen(),
      guards: [
        AuthGuard(
          isAuthenticated: () => BlocScope.get<AuthBloc>().state.isAuthenticated,
        ),
        RoleGuard(
          hasRole: () => BlocScope.get<AuthBloc>().state.user?.roles.contains('admin') ?? false,
          roleName: 'admin',
        ),
      ],
    ),
  ],
);
```

### With juice_network (Interceptors)

AuthBloc provides tokens — it does not depend on juice_network:

```dart
// In app setup:
final fetchBloc = FetchBloc(
  authIdentityProvider: () => BlocScope.get<AuthBloc>().state.userId,
  interceptors: [
    AuthInterceptor(
      tokenProvider: () async => BlocScope.get<AuthBloc>().state.accessToken,
      skipAuth: (path) => path.startsWith('/auth/'),
    ),
    RefreshTokenInterceptor(
      dio: dio,
      refreshToken: () async {
        final authBloc = BlocScope.get<AuthBloc>();
        authBloc.send(RefreshTokenEvent());
        // Await the refresh result
        await authBloc.stream
            .firstWhere((state) => !state.isRefreshing);
        return authBloc.state.accessToken;
      },
      onRefreshFailed: () async {
        BlocScope.get<AuthBloc>().send(LogoutEvent(force: true));
      },
    ),
  ],
);
```

### With juice_storage (Token Persistence)

AuthBloc uses StorageBloc internally for secure token storage:

```dart
// Internal to AuthBloc use cases:
Future<void> _persistTokens(AuthResult result) async {
  final storage = BlocScope.get<StorageBloc>();

  await storage.secureWrite(
    bloc.config.accessTokenKey,
    result.accessToken,
  );

  if (result.refreshToken != null && bloc.config.persistRefreshToken) {
    await storage.secureWrite(
      bloc.config.refreshTokenKey,
      result.refreshToken!,
    );
  }

  // Store session metadata (provider, expiry) as JSON
  await storage.secureWrite(
    bloc.config.sessionKey,
    jsonEncode({
      'providerName': result.user.id, // for restore
      'expiresAt': result.expiresAt?.toIso8601String(),
    }),
  );
}

Future<void> _clearStoredTokens() async {
  final storage = BlocScope.get<StorageBloc>();
  await storage.secureDelete(bloc.config.accessTokenKey);
  await storage.secureDelete(bloc.config.refreshTokenKey);
  await storage.secureDelete(bloc.config.sessionKey);
  await storage.secureDelete(bloc.config.userKey);
}
```

---

## Convenience Methods

```dart
/// On AuthBloc — same pattern as RoutingBloc convenience methods
class AuthBloc extends JuiceBloc<AuthState> {
  late final AuthConfig config;

  /// Login with email/password
  void loginWithEmail(String email, String password) => send(LoginEvent(
    providerName: 'email',
    credentials: EmailCredentials(email: email, password: password),
  ));

  /// Login with OAuth provider
  void loginWithOAuth(String provider, String idToken, {String? accessToken}) =>
      send(LoginEvent(
        providerName: provider,
        credentials: OAuthCredentials(
          provider: provider,
          idToken: idToken,
          accessToken: accessToken,
        ),
      ));

  /// Logout
  void logout({bool force = false}) => send(LogoutEvent(force: force));

  /// Refresh token manually
  void refreshToken() => send(RefreshTokenEvent());

  /// Update user profile
  void updateUser(AuthUser user) => send(UpdateUserEvent(updatedUser: user));

  /// Quick auth check for guards
  bool get isAuthenticated => state.isAuthenticated;
}
```

---

## Error Handling

### AuthError Hierarchy

```dart
sealed class AuthError {
  String get message;

  /// Provider returned an error (wrong password, account locked, etc.)
  factory AuthError.providerError(String message, {required String providerName}) =
      ProviderAuthError;

  /// Unknown provider name
  factory AuthError.unknownProvider(String providerName) = UnknownProviderError;

  /// Token refresh failed
  factory AuthError.refreshFailed(String reason) = RefreshFailedError;

  /// No refresh token available
  factory AuthError.noRefreshToken() = NoRefreshTokenError;

  /// Too many login attempts
  factory AuthError.rateLimited(Duration cooldown) = RateLimitedError;

  /// Secure storage operation failed
  factory AuthError.storageFailed(String operation, String reason) =
      StorageAuthError;

  /// Session restore failed
  factory AuthError.restoreFailed(String reason) = RestoreFailedError;
}
```

```dart
/// Provider returned an error
class ProviderAuthError extends AuthError {
  final String providerName;
  @override
  final String message;
  ProviderAuthError(this.message, {required this.providerName});
}

/// Unknown provider name in LoginEvent
class UnknownProviderError extends AuthError {
  final String providerName;
  UnknownProviderError(this.providerName);
  @override
  String get message => 'Unknown auth provider: $providerName';
}

/// Token refresh failed
class RefreshFailedError extends AuthError {
  final String reason;
  RefreshFailedError(this.reason);
  @override
  String get message => 'Token refresh failed: $reason';
}

/// No refresh token to refresh with
class NoRefreshTokenError extends AuthError {
  @override
  String get message => 'No refresh token available';
}

/// Too many login attempts
class RateLimitedError extends AuthError {
  final Duration cooldown;
  RateLimitedError(this.cooldown);
  @override
  String get message =>
      'Too many login attempts. Try again in ${cooldown.inSeconds}s';
}

/// Secure storage failed
class StorageAuthError extends AuthError {
  final String operation;
  final String reason;
  StorageAuthError(this.operation, this.reason);
  @override
  String get message => 'Auth storage $operation failed: $reason';
}

/// Session restore failed
class RestoreFailedError extends AuthError {
  final String reason;
  RestoreFailedError(this.reason);
  @override
  String get message => 'Session restore failed: $reason';
}
```

### AuthProviderException

```dart
/// Thrown by AuthProvider implementations.
/// Wraps provider-specific errors into a common type.
class AuthProviderException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AuthProviderException(
    this.message, {
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'AuthProviderException: $message (code: $code)';
}
```

---

## Testing

### BlocTester Integration

```dart
test('login with email succeeds', () async {
  final mockProvider = MockEmailAuthProvider();
  when(() => mockProvider.authenticate(any())).thenAnswer((_) async =>
    AuthResult(
      accessToken: 'access-123',
      refreshToken: 'refresh-456',
      expiresAt: DateTime.now().add(Duration(hours: 1)),
      user: AuthUser(id: 'user-1', email: 'test@example.com'),
    ),
  );

  final tester = BlocTester<AuthBloc, AuthState>(
    bloc: AuthBloc(config: AuthConfig(
      providers: {'email': mockProvider},
    )),
  );

  await tester.send(LoginEvent(
    providerName: 'email',
    credentials: EmailCredentials(email: 'test@example.com', password: 'secret'),
  ));

  tester.expectState((state) {
    expect(state.isAuthenticated, true);
    expect(state.user?.email, 'test@example.com');
    expect(state.session?.accessToken, 'access-123');
    expect(state.session?.providerName, 'email');
  });
});

test('login with wrong password emits error', () async {
  final mockProvider = MockEmailAuthProvider();
  when(() => mockProvider.authenticate(any())).thenThrow(
    AuthProviderException('Invalid credentials', code: 'INVALID_PASSWORD'),
  );

  final tester = BlocTester<AuthBloc, AuthState>(
    bloc: AuthBloc(config: testConfig(provider: mockProvider)),
  );

  await tester.send(LoginEvent(
    providerName: 'email',
    credentials: EmailCredentials(email: 'test@example.com', password: 'wrong'),
  ));

  tester.expectState((state) {
    expect(state.isAuthenticated, false);
    expect(state.lastError, isA<ProviderAuthError>());
  });
});

test('logout clears all session state', () async {
  final tester = BlocTester<AuthBloc, AuthState>(
    bloc: authenticatedAuthBloc(), // Helper that returns logged-in bloc
  );

  await tester.send(LogoutEvent());

  tester.expectState((state) {
    expect(state.isAuthenticated, false);
    expect(state.user, isNull);
    expect(state.session, isNull);
    expect(state.status, AuthStatus.unauthenticated);
  });
});

test('concurrent token refresh triggers single refresh', () async {
  var refreshCallCount = 0;
  final mockProvider = MockEmailAuthProvider();
  when(() => mockProvider.refreshToken(any())).thenAnswer((_) async {
    refreshCallCount++;
    await Future.delayed(Duration(milliseconds: 100)); // Simulate network
    return AuthResult(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
      user: testUser,
    );
  });

  final tester = BlocTester<AuthBloc, AuthState>(
    bloc: authenticatedAuthBloc(provider: mockProvider),
  );

  // Fire 5 refresh events simultaneously
  await Future.wait([
    tester.send(RefreshTokenEvent()),
    tester.send(RefreshTokenEvent()),
    tester.send(RefreshTokenEvent()),
    tester.send(RefreshTokenEvent()),
    tester.send(RefreshTokenEvent()),
  ]);

  expect(refreshCallCount, equals(1)); // Singleflight
  tester.expectState((state) {
    expect(state.session?.accessToken, 'new-access');
    expect(state.isRefreshing, false);
  });
});

test('session restore with valid refresh token', () async {
  // Pre-store tokens in mock secure storage
  await mockStorage.secureWrite('juice_auth_refresh_token', 'stored-refresh');
  await mockStorage.secureWrite('juice_auth_session', jsonEncode({
    'providerName': 'email',
  }));

  final tester = BlocTester<AuthBloc, AuthState>(
    bloc: AuthBloc(config: testConfig()),
  );

  // AuthBloc initializes → reads stored token → refreshes → authenticated
  await tester.waitForStatus(AuthStatus.authenticated);

  tester.expectState((state) {
    expect(state.isAuthenticated, true);
    expect(state.session?.providerName, 'email');
  });
});

test('session restore with expired refresh token goes to unauthenticated', () async {
  await mockStorage.secureWrite('juice_auth_refresh_token', 'expired-refresh');
  await mockStorage.secureWrite('juice_auth_session', jsonEncode({
    'providerName': 'email',
  }));

  final mockProvider = MockEmailAuthProvider();
  when(() => mockProvider.refreshToken('expired-refresh'))
    .thenThrow(AuthProviderException('Token expired', code: 'TOKEN_EXPIRED'));

  final tester = BlocTester<AuthBloc, AuthState>(
    bloc: AuthBloc(config: testConfig(provider: mockProvider)),
  );

  await tester.waitForStatus(AuthStatus.unauthenticated);

  tester.expectState((state) {
    expect(state.isAuthenticated, false);
    expect(state.status, AuthStatus.unauthenticated);
  });
});

test('rate limiting after max login attempts', () async {
  final mockProvider = MockEmailAuthProvider();
  when(() => mockProvider.authenticate(any()))
    .thenThrow(AuthProviderException('Wrong password'));

  final tester = BlocTester<AuthBloc, AuthState>(
    bloc: AuthBloc(config: AuthConfig(
      providers: {'email': mockProvider},
      maxLoginAttempts: 3,
      loginCooldown: Duration(seconds: 10),
    )),
  );

  // Fail 3 times
  for (var i = 0; i < 3; i++) {
    await tester.send(LoginEvent(
      providerName: 'email',
      credentials: EmailCredentials(email: 'test@example.com', password: 'wrong'),
    ));
  }

  // 4th attempt is rate limited
  await tester.send(LoginEvent(
    providerName: 'email',
    credentials: EmailCredentials(email: 'test@example.com', password: 'wrong'),
  ));

  tester.expectState((state) {
    expect(state.lastError, isA<RateLimitedError>());
  });
});
```

---

## Implementation Phases

### Phase 1: Core MVP

1. **AuthState + AuthStatus**
   - Immutable state with `copyWith`
   - `unknown → unauthenticated → authenticated` transitions
   - `AuthUser`, `AuthSession` models

2. **AuthProvider interface**
   - `authenticate()`, `refreshToken()`, `revokeSession()`
   - `AuthCredentials` hierarchy (Email, OAuth, ApiKey)
   - `AuthResult` model

3. **Login/Logout use cases**
   - `LoginUseCase` with provider delegation
   - `LogoutUseCase` with atomic cleanup
   - Rebuild groups: `auth:status`, `auth:user`, `auth:session`, `auth:error`

4. **Token persistence**
   - Store tokens in `StorageBloc` secure storage
   - Clear on logout
   - Key prefix for multi-app isolation

5. **Session restore**
   - `RestoreSessionUseCase` on init
   - Read stored refresh token → refresh → authenticated (or clear)

**Phase 1 does NOT include:**
- Token refresh timer (Phase 2)
- Singleflight refresh (Phase 2)
- Multi-account (Phase 3)
- Biometric unlock (Phase 3)
- Login rate limiting (Phase 2)

### Phase 2: Token Lifecycle

- [ ] Proactive refresh timer (fires before `expiresAt`)
- [ ] Singleflight refresh pattern (`Completer`-based)
- [ ] `sessionExpired` status (refresh failed → distinct from unauthenticated)
- [ ] Login rate limiting (`maxLoginAttempts`, cooldown)
- [ ] Aviator integration (`loginSuccess`, `logoutComplete`, `sessionExpired`)
- [ ] `RefreshTokenEvent` for manual refresh

### Phase 3: Advanced

- [ ] Multi-account support (`SwitchAccountEvent`, stored accounts list)
- [ ] Biometric unlock (`BiometricCredentials`, platform integration)
- [ ] Profile sync (`fetchUser()` on provider)
- [ ] Session analytics (login count, provider usage, session duration)
- [ ] Scope integration with `ScopeLifecycleBloc`

---

## Open Questions

1. **OAuth flow orchestration**: Should AuthBloc own the platform OAuth flow (Google Sign-In, Apple Sign-In), or should `OAuthCredentials` come pre-populated from a separate UI coordinator? Leaning toward pre-populated — AuthBloc shouldn't know about `google_sign_in` package.

2. **Multi-factor auth**: How should MFA challenges flow? Possible: `authenticate()` returns `AuthResult` or `MfaChallenge`, and a second `VerifyMfaEvent` completes the flow.

3. **Offline login**: Should AuthBloc allow "offline authentication" using cached credentials when there's no network? Or is that a provider concern?

4. **Token encryption at rest**: Should tokens be encrypted before secure storage, or is platform secure storage (Keychain/Keystore) sufficient?

5. **Refresh token rotation**: Some providers return a new refresh token on each refresh. The spec handles this (`result.refreshToken ?? session.refreshToken`), but should there be explicit rotation tracking?

---

## Summary of Contract Guarantees

| Guarantee | Behavior |
|-----------|----------|
| **Single source** | `authBloc.state.isAuthenticated` — synchronous, reactive, one place |
| **Atomic login** | Fully authenticated or unchanged — no partial states |
| **Atomic logout** | Tokens, storage, cache all cleared in deterministic order |
| **Singleflight refresh** | N concurrent refreshes → 1 provider call, N completers resolved |
| **Session expiry** | `sessionExpired` is distinct from `unauthenticated` |
| **Provider isolation** | AuthBloc never imports Firebase/Supabase — providers are injected |
| **Credential safety** | Passwords never in state, tokens in secure storage |
| **Rate limiting** | Login attempts capped with configurable cooldown |

---

## API Summary

| Type | Purpose |
|------|---------|
| `AuthBloc` | Primary bloc — owns auth lifecycle |
| `AuthState` | Immutable session state |
| `AuthStatus` | `unknown`, `unauthenticated`, `authenticated`, `sessionExpired` |
| `AuthUser` | User identity (id, name, email, roles, metadata) |
| `AuthSession` | Token container (access, refresh, expiry, provider) |
| `AuthConfig` | Bloc configuration (providers, refresh buffer, storage keys) |
| `AuthProvider` | Abstract interface for auth backends |
| `AuthCredentials` | Base class for provider-specific credentials |
| `EmailCredentials` | Email + password |
| `OAuthCredentials` | OAuth tokens from platform flow |
| `ApiKeyCredentials` | API key for service auth |
| `BiometricCredentials` | Biometric unlock with stored token |
| `AuthResult` | Provider response (tokens + user) |
| `AuthError` | Sealed error hierarchy |
| `AuthProviderException` | Thrown by providers, caught by use cases |
| `AuthGroups` | Rebuild group constants (`status`, `user`, `session`, `error`) |
| `LoginEvent` | Login with provider + credentials |
| `LogoutEvent` | Logout with optional force |
| `RefreshTokenEvent` | Manual token refresh |
| `UpdateUserEvent` | Update user profile in state |
| `SwitchAccountEvent` | Switch stored account (Phase 3) |
| `LoginUseCase` | Handles `LoginEvent` |
| `LogoutUseCase` | Handles `LogoutEvent` |
| `RefreshTokenUseCase` | Handles `RefreshTokenEvent` with singleflight |
| `RestoreSessionUseCase` | Handles `InitializeAuthEvent`, restores stored session |
| `UpdateUserUseCase` | Handles `UpdateUserEvent` |

---

## Implementation Notes

These are the intentional divergences between this design contract and the
shipping implementation. **The code is the source of truth**; this section
documents where it deviates and why.

### Events extend `EventBase`, not `ResultEvent`

Auth events (`LoginEvent`, `LogoutEvent`, `RefreshTokenEvent`, …) extend the
core Juice `EventBase`. There is no per-event `result` future to await — outcomes
are observed via `AuthState` (`status`, `lastError`, `user`, `session`) and the
bloc's `StreamStatus` rebuild groups.

### Phase 3 features not implemented

The roadmap items under [Implementation Phases → Phase 3](#phase-3-advanced)
(e.g. `SwitchAccountEvent`, multi-account storage) are deferred and are not
present in the shipping code. The current implementation corresponds to Phase 1
+ Phase 2 of the original plan.

### Singleflight guard uses a public `refreshInFlight` field

The `RefreshTokenUseCase`'s singleflight guard is implemented on
`AuthBloc.refreshInFlight` (a public `Completer<String?>?` on the bloc) rather
than encapsulated inside the use case. This is intentional: it lets future
internal callers (e.g. the auto-refresh timer / `TokenExpiryUseCase`) share the
same in-flight gate. The completer's future is `.ignore()`-ed so an orphan
(no concurrent caller) does not surface as an unhandled async error.

---

## Spec Version

| Version | Date | Status | Changes |
|---------|------|--------|---------|
| 0.1 | - | Draft | Initial spec |
| 0.2 | - | Implemented | Reconciled with shipping code; added [Implementation Notes](#implementation-notes) (code is source of truth) |
