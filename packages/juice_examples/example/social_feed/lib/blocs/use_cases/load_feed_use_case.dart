import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import '../feed_bloc.dart';
import '../feed_events.dart';
import '../../models/post.dart';

class LoadFeedUseCase extends UseCase<FeedBloc, LoadFeedEvent> {
  @override
  Future<void> execute(LoadFeedEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(isLoadingMore: true, currentPage: 0),
    );

    try {
      await bloc.fetchBloc.send(GetEvent(
        url: 'https://dummyjson.com/posts',
        queryParams: {'limit': 10, 'skip': 0},
        cachePolicy: CachePolicy.staleWhileRevalidate,
        ttl: const Duration(minutes: 5),
        decode: (raw) {
          final data = raw as Map<String, dynamic>;
          final list = data['posts'] as List<dynamic>;
          final total = data['total'] as int;
          final posts = list
              .map((e) => Post.fromJson(e as Map<String, dynamic>))
              .toList();
          emitUpdate(
            newState: bloc.state.copyWith(
              posts: posts,
              currentPage: 0,
              hasReachedEnd: posts.length >= total,
              isLoadingMore: false,
            ),
          );
          return posts;
        },
      ));
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(isLoadingMore: false),
        error: e,
      );
    }
  }
}
