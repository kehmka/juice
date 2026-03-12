import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import '../profile_bloc.dart';
import '../profile_events.dart';
import '../../models/user_profile.dart';
import '../../models/post.dart';

class LoadProfileUseCase extends UseCase<ProfileBloc, LoadProfileEvent> {
  @override
  Future<void> execute(LoadProfileEvent event) async {
    emitWaiting(newState: bloc.state.copyWith(isLoading: true));

    try {
      // Load user profile with cacheFirst (rarely changes)
      await bloc.fetchBloc.send(GetEvent(
        url: 'https://dummyjson.com/users/${event.userId}',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 30),
        decode: (raw) {
          final profile =
              UserProfile.fromJson(raw as Map<String, dynamic>);
          emitUpdate(
            newState: bloc.state.copyWith(profile: profile),
          );
          return profile;
        },
      ));

      // Load user's posts
      await bloc.fetchBloc.send(GetEvent(
        url: 'https://dummyjson.com/posts/user/${event.userId}',
        cachePolicy: CachePolicy.staleWhileRevalidate,
        ttl: const Duration(minutes: 5),
        decode: (raw) {
          final data = raw as Map<String, dynamic>;
          final list = data['posts'] as List<dynamic>;
          final posts = list
              .map((e) => Post.fromJson(e as Map<String, dynamic>))
              .toList();
          emitUpdate(
            newState: bloc.state.copyWith(
              userPosts: posts,
              isLoading: false,
            ),
          );
          return posts;
        },
      ));
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(isLoading: false),
        error: e,
      );
    }
  }
}
