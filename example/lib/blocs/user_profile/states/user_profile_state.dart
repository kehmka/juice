import 'package:juice/juice.dart';

class UserProfileState extends BlocState {
  final String? userId;
  final String? displayName;
  final String? avatarUrl;
  final bool isLoading;
  final String? error;

  const UserProfileState({
    this.userId,
    this.displayName,
    this.avatarUrl,
    this.isLoading = false,
    this.error,
  });

  bool get hasProfile => userId != null && displayName != null;

  UserProfileState copyWith({
    String? userId,
    String? displayName,
    String? avatarUrl,
    bool? isLoading,
    String? error,
  }) {
    return UserProfileState(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  @override
  String toString() =>
      'UserProfileState(userId: $userId, displayName: $displayName, isLoading: $isLoading)';
}
