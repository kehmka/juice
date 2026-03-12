import 'package:juice/juice.dart';
import '../feed_bloc.dart';
import '../feed_events.dart';

class LikePostUseCase extends UseCase<FeedBloc, LikePostEvent> {
  @override
  Future<void> execute(LikePostEvent event) async {
    final updatedPosts = bloc.state.posts.map((p) {
      if (p.id == event.postId) {
        return p.copyWith(likes: p.likes + 1);
      }
      return p;
    }).toList();

    final updatedSelected = bloc.state.selectedPost?.id == event.postId
        ? bloc.state.selectedPost!
            .copyWith(likes: bloc.state.selectedPost!.likes + 1)
        : bloc.state.selectedPost;

    emitUpdate(
      newState: bloc.state.copyWith(
        posts: updatedPosts,
        selectedPost: updatedSelected,
      ),
    );
  }
}
