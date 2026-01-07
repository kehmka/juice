# juice_auth

> Canonical specification for the juice_auth companion package

## Purpose

Authentication and authorization workflows including login, logout, token refresh, and session management.

---

## Dependencies

**External:** None

**Juice Packages:**
- juice_network - API calls
- juice_storage - Secure token storage

---

## Architecture

### Bloc: `AuthBloc`

**Lifecycle:** Permanent

### State

```dart
class AuthState extends BlocState {
  final AuthStatus status; // unauthenticated, authenticating, authenticated, refreshing
  final User? currentUser;
  final AuthTokens? tokens;
  final DateTime? tokenExpiry;
  final AuthError? lastError;
  final Set<String> permissions;
}
```

### Events

- `LoginEvent` - Username/password or OAuth login
- `LogoutEvent` - Clear session and tokens
- `RefreshTokenEvent` - Refresh access token
- `CheckAuthStatusEvent` - Restore session from storage
- `UpdatePermissionsEvent` - Update user permissions
- `BiometricAuthEvent` - Biometric authentication

### Rebuild Groups

- `auth:status` - Authentication state changes
- `auth:user` - User profile changes
- `auth:permissions` - Permission changes

---

## Integration Points

**StateRelay to:**
- juice_network - Authorization header injection

**EventSubscription to:**
- juice_analytics - Auth events tracking

---

## Open Questions

_To be discussed_
