import 'package:juice/juice.dart';

class AuthState extends BlocState {
  final String? userId;
  final String? email;
  final bool isAuthenticated;
  final bool isLoading;

  const AuthState({
    this.userId,
    this.email,
    this.isAuthenticated = false,
    this.isLoading = false,
  });

  AuthState copyWith({
    String? userId,
    String? email,
    bool? isAuthenticated,
    bool? isLoading,
  }) {
    return AuthState(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  String toString() =>
      'AuthState(userId: $userId, email: $email, isAuthenticated: $isAuthenticated)';
}
