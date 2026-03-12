import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import 'feed_state.dart';
import 'feed_events.dart';
import 'use_cases/load_feed_use_case.dart';
import 'use_cases/load_more_use_case.dart';
import 'use_cases/like_post_use_case.dart';
import 'use_cases/add_comment_use_case.dart';
import 'use_cases/select_post_use_case.dart';

class FeedBloc extends JuiceBloc<FeedState> {
  final FetchBloc fetchBloc;

  FeedBloc({required this.fetchBloc})
      : super(
          const FeedState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadFeedEvent,
                  useCaseGenerator: () => LoadFeedUseCase(),
                  initialEventBuilder: () => LoadFeedEvent(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LoadMoreEvent,
                  useCaseGenerator: () => LoadMoreUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LikePostEvent,
                  useCaseGenerator: () => LikePostUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: AddCommentEvent,
                  useCaseGenerator: () => AddCommentUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SelectPostEvent,
                  useCaseGenerator: () => SelectPostUseCase(),
                ),
          ],
        );
}
