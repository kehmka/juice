---
card_schema: "1.0"
package: juice_auth
version: 0.2.1
requires:
  juice: ">=1.4.0"
  juice_storage: ">=1.2.0"
updated: 2026-06-09
---

# juice_auth — AI card

> Provider-agnostic authentication lifecycle: login, proactive token refresh,
> session persistence, restore-on-launch, and reactive auth state — backend
> logic behind an `AuthProvider` seam. Read repo `AGENTS.md` for the Juice mental
> model + gotchas.

## Purpose

**Owns:** the auth state machine (`unknown → unauthenticated / authenticated /
sessionExpired`), token/session persistence (secure storage via `juice_storage`),
the proactive refresh timer + singleflight, and login rate-limiting.
**Does NOT own:** how a backend authenticates (the `AuthProvider` seam — REST,
Firebase, Supabase…), HTTP token injection (use `juice_auth_network`), or route
guarding (use `juice_auth_routing`).

## Install

```yaml
dependencies:
  juice_auth: ^0.2.1
  juice_storage: ^1.2.0   # required — secure token/session storage
```

## Construct

`storageBloc` is **required** (token persistence). At least one `AuthProvider`
keyed by name is required in config:

```dart
final auth = AuthBloc.withConfig(
  AuthConfig(
    providers: {'email': MyApiAuthProvider()},   // keyed by provider name
    refreshBuffer: const Duration(seconds: 60),   // refresh this long before expiry
    restoreSessionOnInit: true,                   // restore on InitializeAuthEvent
    maxLoginAttempts: 5, loginCooldown: const Duration(seconds: 30),
    persistRefreshToken: true, storagePrefix: 'juice_auth',
  ),
  storageBloc: storageBloc,
);
// Equivalent to: AuthBloc(storageBloc: ...) then send(InitializeAuthEvent(config: ...)).
```

## Seams

```dart
// REQUIRED. One per backend / login method, keyed by `name` in AuthConfig.providers.
abstract class AuthProvider {
  String get name;                                            // 'email' | 'google' | …
  Future<AuthResult> authenticate(AuthCredentials c);         // throw AuthProviderException on fail
  Future<AuthResult> refreshToken(String refreshToken);       // throw → session invalid
  Future<void> revokeSession(AuthSession s);                  // best-effort; MUST NOT throw
  Future<AuthUser?> fetchUser(String accessToken) async => null;  // optional profile sync
  bool get supportsRefresh => true;
  Future<void> dispose() async {}
}
// AuthResult: accessToken, refreshToken?, expiresAt?, user?
// AuthCredentials: EmailCredentials(email,password) | OAuthCredentials(provider,idToken,accessToken?)
// AuthProviderException(message, code?, originalError?)
```

## API

`AuthBloc` (thin wrappers over events; `bloc.state` is the source of truth):

```dart
factory AuthBloc.withConfig(AuthConfig config, {required StorageBloc storageBloc});
void loginWithEmail(String email, String password);
void loginWithOAuth(String provider, String idToken, {String? accessToken});
void logout({bool force = false});      // force → skip provider revocation
void refreshToken();                    // usually automatic; manual override
void updateUser(AuthUser user);
AuthConfig get config;
```

## Events

| Event | Effect |
|---|---|
| `InitializeAuthEvent(config)` | set config; restore session if `restoreSessionOnInit` |
| `LoginEvent(providerName, credentials)` | authenticate via the named provider, persist, schedule refresh |
| `LogoutEvent(force?)` | revoke (unless `force`), clear storage, → `unauthenticated` |
| `RefreshTokenEvent()` | manual token refresh (singleflight) |
| `UpdateUserEvent(updatedUser)` | replace `state.user` |
| `TokenExpiryEvent()` *internal* | fired by the refresh timer at `expiresAt − refreshBuffer` |

## State

```dart
class AuthState extends BlocState {              // immutable
  AuthStatus status;                              // unknown|unauthenticated|authenticated|sessionExpired
  AuthUser? user; AuthSession? session; AuthError? lastError;
  bool isRefreshing; String? pendingProvider;
  int loginAttempts; DateTime? loginCooldownUntil;
  bool get isAuthenticated; bool get isSessionExpired; bool get isRateLimited;
  String? get userId; String? get accessToken; bool hasRole(String role);
}
// AuthSession: accessToken, refreshToken?, expiresAt?, providerName, createdAt, lastRefreshedAt?, isExpired
```

`sessionExpired` is distinct from `unauthenticated` on purpose — a UI can show
"session ended, please sign in again" vs. a cold logged-out state.

## Rebuild groups

| Group | Emitted when |
|---|---|
| `AuthGroups.status` → `auth:status` | login / logout / session expiry (status change) |
| `AuthGroups.user` → `auth:user` | profile changed |
| `AuthGroups.session` → `auth:session` | token refresh / session update |
| `AuthGroups.error` → `auth:error` | an `AuthError` occurred |

## Concurrency

Token refresh is **singleflight** via `AuthBloc.refreshInFlight` (a shared
`Completer<String?>`): concurrent triggers (the timer, a manual call, a
`juice_auth_network` 401) collapse into one provider `refreshToken` call; all
callers await the same result. Don't add a second refresh path.

## Recipes

```dart
// 1. Implement the provider seam.
class MyApiAuthProvider extends AuthProvider {
  @override String get name => 'email';
  @override Future<AuthResult> authenticate(AuthCredentials c) async {
    final e = c as EmailCredentials;
    final r = await api.login(e.email, e.password);
    return AuthResult(accessToken: r.access, refreshToken: r.refresh,
        expiresAt: r.expiresAt, user: AuthUser(id: r.userId, email: e.email));
  }
  @override Future<AuthResult> refreshToken(String t) => api.refresh(t).then(_toResult);
  @override Future<void> revokeSession(AuthSession s) async { try { await api.logout(); } catch (_) {} }
}

// 2. Gate the app on auth status.
class AuthGate extends StatelessJuiceWidget<AuthBloc> {
  AuthGate({super.key}) : super(groups: {AuthGroups.status});
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      bloc.state.isAuthenticated ? HomeScreen() : LoginScreen();
}
```

## Testing

Headless — fake the `AuthProvider`, use a fake `StorageBloc`.

```dart
class FakeProvider extends AuthProvider {
  @override String get name => 'email';
  @override Future<AuthResult> authenticate(_) async =>
      AuthResult(accessToken: 't', expiresAt: DateTime.now().add(const Duration(hours: 1)),
                 user: const AuthUser(id: 'u1'));
  @override Future<AuthResult> refreshToken(_) async => throw const AuthProviderException('no');
  @override Future<void> revokeSession(_) async {}
}
final auth = AuthBloc.withConfig(AuthConfig(providers: {'email': FakeProvider()}), storageBloc: fakeStorage);
auth.loginWithEmail('a@b.c', 'pw');
await settle();
expect(auth.state.isAuthenticated, isTrue);
```

## Failure modes

- Errors are a sealed `AuthError`: `ProviderAuthError` (auth failed),
  `UnknownProviderError` (name not in config), `RefreshFailedError`,
  `NoRefreshTokenError`, `RateLimitedError` (over `maxLoginAttempts`),
  `StorageAuthError`, `RestoreFailedError`.
- A **failed refresh → `sessionExpired`** (not silent re-login) so the UI can
  react; the original caller (e.g. a 401 retry) sees `null`/failure.
- `revokeSession` failures are swallowed by contract — logout still completes
  locally even if the server revoke call fails.
- Over the login-attempt limit → `isRateLimited` / `RateLimitedError` until
  `loginCooldownUntil`.

## Anti-patterns

- ❌ Importing a vendor auth SDK into a bloc/use-case — put it behind an
  `AuthProvider` impl.
- ❌ Adding a second refresh trigger that bypasses `refreshInFlight` — breaks
  singleflight, causes a refresh storm.
- ❌ Storing the access token in `AuthState` and reading it from elsewhere as the
  *persistence* — persistence is secure storage; state is the live view.
- ❌ Treating `sessionExpired` as `unauthenticated` — they're deliberately
  distinct.

## Integrates with

- **juice_storage** — required; secure read/write of tokens + session metadata.
- **juice_network** via **juice_auth_network** — token injection, 401 refresh,
  per-user cache isolation (`AuthBlocIdentityProvider`).
- **juice_routing** via **juice_auth_routing** — auth-driven guards + reactive
  redirect.

## Invariants

- The refresh timer fires `TokenExpiryEvent` at `expiresAt − refreshBuffer`; if
  already past, it refreshes immediately.
- `close()` cancels the refresh timer and disposes every provider.
- Provider `name` must match the key it's registered under in
  `AuthConfig.providers`.

## See also

`doc/SPEC.md` (design depth) · repo `AGENTS.md` (framework).
