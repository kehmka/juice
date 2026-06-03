import 'package:juice_auth/juice_auth.dart';

/// A self-contained [AuthProvider] for the demo.
///
/// Implementing [AuthProvider] is the framework's intended extension point for
/// any backend. This one returns canned credentials so the demo needs no auth
/// server; `refreshToken` rotates the access token so the refresh button shows
/// a visibly new value.
class DemoAuthProvider extends AuthProvider {
  int _refreshCount = 0;

  @override
  String get name => 'email';

  @override
  Future<AuthResult> authenticate(AuthCredentials credentials) async {
    return AuthResult(
      accessToken: 'access-token-initial',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      user: const AuthUser(
        id: 'user-ada',
        email: 'ada@demo.dev',
        displayName: 'Ada Lovelace',
      ),
    );
  }

  @override
  Future<AuthResult> refreshToken(String refreshToken) async {
    _refreshCount++;
    return AuthResult(
      accessToken: 'access-token-refreshed-$_refreshCount',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      user: const AuthUser(
        id: 'user-ada',
        email: 'ada@demo.dev',
        displayName: 'Ada Lovelace',
      ),
    );
  }

  @override
  Future<void> revokeSession(AuthSession session) async {}
}
