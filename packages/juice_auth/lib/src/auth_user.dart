import 'package:flutter/foundation.dart';

/// Represents an authenticated user.
@immutable
class AuthUser {
  /// Unique user identifier.
  final String id;

  /// Display name.
  final String? displayName;

  /// Email address.
  final String? email;

  /// Profile photo URL.
  final String? photoUrl;

  /// User roles (for RoleGuard integration).
  final Set<String> roles;

  /// Provider-specific metadata (Firebase UID, OAuth claims, etc.).
  final Map<String, dynamic> metadata;

  const AuthUser({
    required this.id,
    this.displayName,
    this.email,
    this.photoUrl,
    this.roles = const {},
    this.metadata = const {},
  });

  AuthUser copyWith({
    String? id,
    String? displayName,
    String? email,
    String? photoUrl,
    Set<String>? roles,
    Map<String, dynamic>? metadata,
  }) {
    return AuthUser(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      roles: roles ?? this.roles,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AuthUser(id: $id, email: $email)';
}
