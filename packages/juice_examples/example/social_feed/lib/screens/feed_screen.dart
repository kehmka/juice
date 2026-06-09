import 'package:juice/juice.dart';
import '../blocs/feed_bloc.dart';
import '../blocs/feed_state.dart';
import '../blocs/feed_events.dart';
import '../models/post.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';

class FeedScreen extends StatelessJuiceWidget<FeedBloc> {
  FeedScreen({super.key}) : super(groups: const {'feed:posts', 'feed:loading'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => bloc.send(LoadFeedEvent()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          bloc.send(LoadFeedEvent());
          // Wait briefly for the state to update
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: _buildFeedList(context, state, status),
      ),
    );
  }

  Widget _buildFeedList(
      BuildContext context, FeedState state, StreamStatus status) {
    if (state.posts.isEmpty && status is WaitingStatus) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.posts.isEmpty) {
      return const Center(child: Text('No posts found'));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 200) {
          bloc.send(LoadMoreEvent());
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.posts.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _PostCard(
            post: state.posts[index],
            onTap: () {
              bloc.send(SelectPostEvent(postId: state.posts[index].id));
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PostDetailScreen()),
              );
            },
            onLike: () =>
                bloc.send(LikePostEvent(postId: state.posts[index].id)),
            onProfileTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ProfileScreen(userId: state.posts[index].userId),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget close(BuildContext context) => const SizedBox.shrink();
}

class _PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onProfileTap;

  const _PostCard({
    required this.post,
    required this.onTap,
    required this.onLike,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: onProfileTap,
                    child: CircleAvatar(
                      radius: 18,
                      child: Text('U${post.userId}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: onProfileTap,
                      child: Text(
                        'User ${post.userId}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  Icon(Icons.visibility, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('${post.views}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                post.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                post.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[700]),
              ),
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: post.tags
                      .map((tag) => Chip(
                            label:
                                Text(tag, style: const TextStyle(fontSize: 11)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  InkWell(
                    onTap: onLike,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.favorite_border,
                              size: 20, color: Colors.red),
                          const SizedBox(width: 4),
                          Text('${post.likes}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.comment_outlined,
                      size: 20, color: Colors.grey),
                  const SizedBox(width: 4),
                  const Text('Comments'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
