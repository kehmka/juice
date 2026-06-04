import 'package:juice_auth/juice_auth.dart';

/// Self-contained [AuthProvider] for the demo — no real backend.
class DemoAuthProvider extends AuthProvider {
  @override
  String get name => 'email';

  @override
  Future<AuthResult> authenticate(AuthCredentials credentials) async {
    return AuthResult(
      accessToken: 'demo-token',
      refreshToken: 'demo-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      user: const AuthUser(
        id: 'user-ada',
        email: 'ada@demo.dev',
        displayName: 'Ada Lovelace',
        roles: {'user'},
      ),
    );
  }

  @override
  Future<AuthResult> refreshToken(String refreshToken) async => authenticate(
        const EmailCredentials(email: 'ada@demo.dev', password: ''),
      );

  @override
  Future<void> revokeSession(AuthSession session) async {}
}
