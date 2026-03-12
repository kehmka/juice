import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import '../feed_bloc.dart';
import '../feed_events.dart';
import '../../models/comment.dart';

class SelectPostUseCase extends UseCase<FeedBloc, SelectPostEvent> {
  @override
  Future<void> execute(SelectPostEvent event) async {
    final post = bloc.state.posts.firstWhere((p) => p.id == event.postId);
    emitUpdate(
      newState: bloc.state.copyWith(
        selectedPost: post,
        selectedPostComments: [],
      ),
    );

    // Load comments for the selected post
    try {
      await bloc.fetchBloc.send(GetEvent(
        url: 'https://dummyjson.com/comments/post/${event.postId}',
        cachePolicy: CachePolicy.staleWhileRevalidate,
        ttl: const Duration(minutes: 5),
        decode: (raw) {
          final data = raw as Map<String, dynamic>;
          final list = data['comments'] as List<dynamic>;
          final comments = list
              .map((e) => Comment.fromJson(e as Map<String, dynamic>))
              .toList();
          emitUpdate(
            newState: bloc.state.copyWith(selectedPostComments: comments),
          );
          return comments;
        },
      ));
    } catch (e) {
      // Silently fail on comment load — post is still visible
    }
  }
}
