import 'package:juice/juice.dart';
import '../feed_bloc.dart';
import '../feed_events.dart';
import '../../models/comment.dart';

class AddCommentUseCase extends UseCase<FeedBloc, AddCommentEvent> {
  @override
  Future<void> execute(AddCommentEvent event) async {
    final newComment = Comment(
      id: DateTime.now().millisecondsSinceEpoch,
      body: event.body,
      postId: event.postId,
      userName: 'you',
    );

    final updatedComments = [
      ...bloc.state.selectedPostComments,
      newComment,
    ];

    emitUpdate(
      newState: bloc.state.copyWith(
        selectedPostComments: updatedComments,
      ),
    );
  }
}
