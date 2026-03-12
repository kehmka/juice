import 'package:juice/juice.dart';
import '../models/post.dart';
import '../models/comment.dart';

class FeedState extends BlocState {
  final List<Post> posts;
  final bool isLoadingMore;
  final int currentPage;
  final bool hasReachedEnd;
  final Post? selectedPost;
  final List<Comment> selectedPostComments;

  const FeedState({
    this.posts = const [],
    this.isLoadingMore = false,
    this.currentPage = 0,
    this.hasReachedEnd = false,
    this.selectedPost,
    this.selectedPostComments = const [],
  });

  FeedState copyWith({
    List<Post>? posts,
    bool? isLoadingMore,
    int? currentPage,
    bool? hasReachedEnd,
    Post? selectedPost,
    List<Comment>? selectedPostComments,
    bool clearSelectedPost = false,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      currentPage: currentPage ?? this.currentPage,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      selectedPost:
          clearSelectedPost ? null : (selectedPost ?? this.selectedPost),
      selectedPostComments:
          selectedPostComments ?? this.selectedPostComments,
    );
  }
}
