import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import '../feed_bloc.dart';
import '../feed_events.dart';
import '../../models/post.dart';

class LoadMoreUseCase extends UseCase<FeedBloc, LoadMoreEvent> {
  @override
  Future<void> execute(LoadMoreEvent event) async {
    if (bloc.state.hasReachedEnd || bloc.state.isLoadingMore) return;

    final nextPage = bloc.state.currentPage + 1;
    final skip = nextPage * 10;
    emitUpdate(newState: bloc.state.copyWith(isLoadingMore: true));

    try {
      await bloc.fetchBloc.send(GetEvent(
        url: 'https://dummyjson.com/posts',
        queryParams: {'limit': 10, 'skip': skip},
        cachePolicy: CachePolicy.networkFirst,
        ttl: const Duration(minutes: 5),
        decode: (raw) {
          final data = raw as Map<String, dynamic>;
          final list = data['posts'] as List<dynamic>;
          final total = data['total'] as int;
          final newPosts = list
              .map((e) => Post.fromJson(e as Map<String, dynamic>))
              .toList();
          final allPosts = [...bloc.state.posts, ...newPosts];
          emitUpdate(
            newState: bloc.state.copyWith(
              posts: allPosts,
              currentPage: nextPage,
              hasReachedEnd: allPosts.length >= total,
              isLoadingMore: false,
            ),
          );
          return newPosts;
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
