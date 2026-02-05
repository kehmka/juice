import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

import '../models/post.dart';

// =============================================================================
// State
// =============================================================================

class PostsState extends BlocState {
  final List<Post> posts;
  final Post? selectedPost;
  final int? selectedPostId;
  final bool isListLoading;
  final bool isDetailLoading;
  final String? listError;
  final String? detailError;
  final CachePolicy cachePolicy;
  final bool postDeleted;

  const PostsState({
    this.posts = const [],
    this.selectedPost,
    this.selectedPostId,
    this.isListLoading = false,
    this.isDetailLoading = false,
    this.listError,
    this.detailError,
    this.cachePolicy = CachePolicy.cacheFirst,
    this.postDeleted = false,
  });

  PostsState copyWith({
    List<Post>? posts,
    Post? selectedPost,
    int? selectedPostId,
    bool? isListLoading,
    bool? isDetailLoading,
    String? listError,
    String? detailError,
    CachePolicy? cachePolicy,
    bool? postDeleted,
    bool clearSelectedPost = false,
    bool clearListError = false,
    bool clearDetailError = false,
  }) {
    return PostsState(
      posts: posts ?? this.posts,
      selectedPost: clearSelectedPost ? null : (selectedPost ?? this.selectedPost),
      selectedPostId: selectedPostId ?? this.selectedPostId,
      isListLoading: isListLoading ?? this.isListLoading,
      isDetailLoading: isDetailLoading ?? this.isDetailLoading,
      listError: clearListError ? null : (listError ?? this.listError),
      detailError: clearDetailError ? null : (detailError ?? this.detailError),
      cachePolicy: cachePolicy ?? this.cachePolicy,
      postDeleted: postDeleted ?? this.postDeleted,
    );
  }
}

// =============================================================================
// Events
// =============================================================================

class LoadPostsEvent extends EventBase {}

class SetCachePolicyEvent extends EventBase {
  final CachePolicy policy;
  SetCachePolicyEvent(this.policy);
}

class LoadPostDetailEvent extends EventBase {
  final int postId;
  LoadPostDetailEvent(this.postId);
}

class DeletePostEvent extends EventBase {}

class ClearPostDetailEvent extends EventBase {}

// =============================================================================
// Use Cases
// =============================================================================

class LoadPostsUseCase extends BlocUseCase<PostsBloc, LoadPostsEvent> {
  @override
  Future<void> execute(LoadPostsEvent event) async {
    emitUpdate(newState: bloc.state.copyWith(isListLoading: true, clearListError: true));

    try {
      await bloc.fetchBloc.send(GetEvent(
        url: '/posts',
        cachePolicy: bloc.state.cachePolicy,
        ttl: const Duration(minutes: 5),
        decode: (raw) {
          // dummyjson.com returns {posts: [...], total, skip, limit}
          final postsData = raw is Map ? raw['posts'] as List : raw as List;
          final posts = Post.fromJsonList(postsData);
          emitUpdate(newState: bloc.state.copyWith(posts: posts, isListLoading: false));
          return posts;
        },
      ));
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(isListLoading: false, listError: e.toString()),
      );
    }
  }
}

class SetCachePolicyUseCase extends BlocUseCase<PostsBloc, SetCachePolicyEvent> {
  @override
  Future<void> execute(SetCachePolicyEvent event) async {
    emitUpdate(newState: bloc.state.copyWith(cachePolicy: event.policy));
  }
}

class LoadPostDetailUseCase extends BlocUseCase<PostsBloc, LoadPostDetailEvent> {
  @override
  Future<void> execute(LoadPostDetailEvent event) async {
    emitUpdate(newState: bloc.state.copyWith(
      selectedPostId: event.postId,
      isDetailLoading: true,
      clearDetailError: true,
      clearSelectedPost: true,
      postDeleted: false,
    ));

    // Check if we already have this post in the list
    final cached = bloc.state.posts.where((p) => p.id == event.postId).firstOrNull;
    if (cached != null) {
      emitUpdate(newState: bloc.state.copyWith(selectedPost: cached, isDetailLoading: false));
      return;
    }

    try {
      await bloc.fetchBloc.send(GetEvent(
        url: '/posts/${event.postId}',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 5),
        decode: (raw) {
          final post = Post.fromJson(raw as Map<String, dynamic>);
          emitUpdate(newState: bloc.state.copyWith(selectedPost: post, isDetailLoading: false));
          return post;
        },
      ));
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(isDetailLoading: false, detailError: e.toString()),
      );
    }
  }
}

class DeletePostUseCase extends BlocUseCase<PostsBloc, DeletePostEvent> {
  @override
  Future<void> execute(DeletePostEvent event) async {
    final postId = bloc.state.selectedPostId;
    if (postId == null) return;

    emitUpdate(newState: bloc.state.copyWith(isDetailLoading: true));

    try {
      await bloc.fetchBloc.send(DeleteEvent(url: '/posts/$postId'));
      emitUpdate(newState: bloc.state.copyWith(isDetailLoading: false, postDeleted: true));
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(isDetailLoading: false, detailError: e.toString()),
      );
    }
  }
}

class ClearPostDetailUseCase extends BlocUseCase<PostsBloc, ClearPostDetailEvent> {
  @override
  Future<void> execute(ClearPostDetailEvent event) async {
    emitUpdate(newState: bloc.state.copyWith(
      clearSelectedPost: true,
      selectedPostId: null,
      clearDetailError: true,
      postDeleted: false,
    ));
  }
}

// =============================================================================
// Bloc
// =============================================================================

class PostsBloc extends JuiceBloc<PostsState> {
  final FetchBloc fetchBloc;

  PostsBloc({required this.fetchBloc})
      : super(
          const PostsState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadPostsEvent,
                  useCaseGenerator: () => LoadPostsUseCase(),
                  initialEventBuilder: () => LoadPostsEvent(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SetCachePolicyEvent,
                  useCaseGenerator: () => SetCachePolicyUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LoadPostDetailEvent,
                  useCaseGenerator: () => LoadPostDetailUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: DeletePostEvent,
                  useCaseGenerator: () => DeletePostUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ClearPostDetailEvent,
                  useCaseGenerator: () => ClearPostDetailUseCase(),
                ),
          ],
        );
}
