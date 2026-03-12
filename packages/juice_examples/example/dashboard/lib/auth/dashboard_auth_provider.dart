import 'package:juice_auth/juice_auth.dart';

/// Fake AuthProvider implementation with hardcoded demo users.
class DashboardAuthProvider extends AuthProvider {
  static const _users = {
    'admin@demo.com': _DemoUser(
      password: 'admin',
      id: 'user-1',
      name: 'Admin User',
      roles: {'admin', 'editor'},
    ),
    'editor@demo.com': _DemoUser(
      password: 'editor',
      id: 'user-2',
      name: 'Editor User',
      roles: {'editor'},
    ),
    'viewer@demo.com': _DemoUser(
      password: 'viewer',
      id: 'user-3',
      name: 'Viewer User',
      roles: {'viewer'},
    ),
  };

  @override
  String get name => 'email';

  @override
  Future<AuthResult> authenticate(AuthCredentials credentials) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    if (credentials is! EmailCredentials) {
      throw const AuthProviderException('Only email login is supported');
    }

    final user = _users[credentials.email];
    if (user == null || user.password != credentials.password) {
      throw const AuthProviderException(
        'Invalid email or password',
        code: 'invalid_credentials',
      );
    }

    return AuthResult(
      accessToken: 'fake-access-token-${user.id}',
      refreshToken: 'fake-refresh-token-${user.id}',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      user: AuthUser(
        id: user.id,
        displayName: user.name,
        email: credentials.email,
        roles: user.roles,
      ),
    );
  }

  @override
  Future<AuthResult> refreshToken(String refreshToken) async {
    await Future.delayed(const Duration(milliseconds: 300));

    // Find user by refresh token pattern
    final userId = refreshToken.replaceFirst('fake-refresh-token-', '');
    final entry = _users.entries.firstWhere(
      (e) => e.value.id == userId,
      orElse: () => throw const AuthProviderException('Invalid refresh token'),
    );

    final user = entry.value;
    return AuthResult(
      accessToken: 'fake-access-token-${user.id}-refreshed',
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      user: AuthUser(
        id: user.id,
        displayName: user.name,
        email: entry.key,
        roles: user.roles,
      ),
    );
  }

  @override
  Future<void> revokeSession(AuthSession session) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // No-op for fake provider
  }
}

class _DemoUser {
  final String password;
  final String id;
  final String name;
  final Set<String> roles;

  const _DemoUser({
    required this.password,
    required this.id,
    required this.name,
    required this.roles,
  });
}
