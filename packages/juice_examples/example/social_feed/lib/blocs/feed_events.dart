import 'package:juice/juice.dart';

class LoadFeedEvent extends EventBase {
  LoadFeedEvent() : super(groupsToRebuild: {'feed:posts', 'feed:loading'});
}

class LoadMoreEvent extends EventBase {
  LoadMoreEvent() : super(groupsToRebuild: {'feed:posts', 'feed:loading'});
}

class LikePostEvent extends EventBase {
  final int postId;
  LikePostEvent({required this.postId})
      : super(groupsToRebuild: {'feed:posts'});
}

class AddCommentEvent extends EventBase {
  final int postId;
  final String body;
  AddCommentEvent({required this.postId, required this.body})
      : super(groupsToRebuild: {'feed:detail'});
}

class SelectPostEvent extends EventBase {
  final int postId;
  SelectPostEvent({required this.postId})
      : super(groupsToRebuild: {'feed:detail'});
}
