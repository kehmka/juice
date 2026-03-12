import 'package:juice/juice.dart';
import '../models/user_profile.dart';
import '../models/post.dart';

class ProfileState extends BlocState {
  final UserProfile? profile;
  final List<Post> userPosts;
  final bool isLoading;

  const ProfileState({
    this.profile,
    this.userPosts = const [],
    this.isLoading = false,
  });

  ProfileState copyWith({
    UserProfile? profile,
    List<Post>? userPosts,
    bool? isLoading,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      userPosts: userPosts ?? this.userPosts,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
