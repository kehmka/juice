# juice_auth

Authentication lifecycle management for [Juice](https://pub.dev/packages/juice) applications. Provider-agnostic login, token refresh, session persistence, and reactive auth state.

[![pub package](https://img.shields.io/pub/v/juice_auth.svg)](https://pub.dev/packages/juice_auth)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## Features

- **Single Source of Truth** — `authBloc.state.isAuthenticated` is synchronous, reactive, and always current
- **Provider Agnostic** — `AuthProvider` interface decouples from Firebase, Supabase, or any backend
- **Automatic Token Lifecycle** — secure storage, silent refresh before expiry, singleflight refresh
- **Atomic Logout** — one event clears tokens, storage, and session in deterministic order
- **Session Expiry Detection** — `sessionExpired` status distinct from `unauthenticated` for proper UX
- **Login Rate Limiting** — configurable max attempts with cooldown duration
- **Testable** — mock `AuthProvider`, send events, assert `AuthState` with `BlocTester`

## Installation

```yaml
dependencies:
  juice_auth: ^0.2.0
```

## Quick Start

### 1. Implement an Auth Provider

```dart
class MyApiAuthProvider extends AuthProvider {
  @override
  String get name => 'email';

  @override
  Future<AuthResult> authenticate(AuthCredentials credentials) async {
    final creds = credentials as EmailCredentials;
    final response = await dio.post('/auth/login', data: {
      'email': creds.email,
      'password': creds.password,
    });
    return AuthResult(
      accessToken: response.data['access_token'],
      refreshToken: response.data['refresh_token'],
      expiresAt: DateTime.parse(response.data['expires_at']),
      user: AuthUser(
        id: response.data['user']['id'],
        email: response.data['user']['email'],
        displayName: response.data['user']['name'],
      ),
    );
  }

  @override
  Future<AuthResult> refreshToken(String refreshToken) async {
    final response = await dio.post('/auth/refresh', data: {
      'refresh_token': refreshToken,
    });
    return AuthResult(
      accessToken: response.data['access_token'],
      refreshToken: response.data['refresh_token'],
      expiresAt: DateTime.parse(response.data['expires_at']),
      user: AuthUser(id: response.data['user']['id']),
    );
  }

  @override
  Future<void> revokeSession(AuthSession session) async {
    try {
      await dio.post('/auth/logout', data: {
        'refresh_token': session.refreshToken,
      });
    } catch (_) {
      // Best-effort — don't block logout
    }
  }
}
```

### 2. Register AuthBloc

```dart
void main() {
  // 1. Storage first (for token persistence)
  BlocScope.register<StorageBloc>(
    () => StorageBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  // 2. AuthBloc
  final storageBloc = BlocScope.get<StorageBloc>();

  BlocScope.register<AuthBloc>(
    () => AuthBloc.withConfig(
      AuthConfig(
        providers: {'email': MyApiAuthProvider()},
      ),
      storageBloc: storageBloc,
    ),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(MyApp());
}
```

### 3. Login

```dart
final authBloc = BlocScope.get<AuthBloc>();
authBloc.loginWithEmail('user@example.com', 'password');
```

### 4. React to Auth State

```dart
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
```

### 5. Integrate with Route Guards

```dart
RouteConfig(
  path: '/profile',
  builder: (ctx) => ProfileScreen(),
  guards: [
    AuthGuard(
      isAuthenticated: () => BlocScope.get<AuthBloc>().state.isAuthenticated,
    ),
  ],
)
```

## Rebuild Groups

| Group | Fires When |
|-------|------------|
| `auth:status` | Login, logout, session expiry |
| `auth:user` | User profile changes |
| `auth:session` | Token refresh, session update |
| `auth:error` | Auth error occurs |

## Integration

| Package | Integration |
|---------|-------------|
| `juice_routing` | Provide `isAuthenticated` callback to `AuthGuard`/`GuestGuard`/`RoleGuard` |
| `juice_network` | Provide `accessToken` to `AuthInterceptor`, `refreshToken` to `RefreshTokenInterceptor` — or use [`juice_auth_network`](https://pub.dev/packages/juice_auth_network) for ready-made adapters |
| `juice_storage` | Tokens stored in secure storage via `StorageBloc` |

## Documentation

- [Getting Started](doc/getting-started.md)
- [API Reference](doc/api.md)
- [Spec](doc/SPEC.md)
