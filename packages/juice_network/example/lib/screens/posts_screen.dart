import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

import '../blocs/blocs.dart';
import '../models/post.dart';
import 'post_detail_screen.dart';

class PostsScreen extends StatelessJuiceWidget<PostsBloc> {
  PostsScreen({super.key});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Posts'),
        actions: [
          PopupMenuButton<CachePolicy>(
            icon: const Icon(Icons.cached),
            tooltip: 'Cache Policy',
            onSelected: (policy) {
              bloc.send(SetCachePolicyEvent(policy));
              bloc.send(LoadPostsEvent());
            },
            itemBuilder: (context) => [
              _buildPolicyItem(CachePolicy.cacheFirst, 'Cache First', state),
              _buildPolicyItem(CachePolicy.networkFirst, 'Network First', state),
              _buildPolicyItem(CachePolicy.networkOnly, 'Network Only', state),
              _buildPolicyItem(CachePolicy.cacheOnly, 'Cache Only', state),
              _buildPolicyItem(CachePolicy.staleWhileRevalidate, 'Stale While Revalidate', state),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => bloc.send(LoadPostsEvent()),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(context, state),
    );
  }

  PopupMenuItem<CachePolicy> _buildPolicyItem(
    CachePolicy policy,
    String label,
    PostsState state,
  ) {
    return PopupMenuItem(
      value: policy,
      child: Row(
        children: [
          if (state.cachePolicy == policy)
            const Icon(Icons.check, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, PostsState state) {
    if (state.isListLoading && state.posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.listError != null && state.posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(state.listError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => bloc.send(LoadPostsEvent()),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => bloc.send(LoadPostsEvent()),
      child: Stack(
        children: [
          ListView.builder(
            itemCount: state.posts.length,
            itemBuilder: (context, index) {
              final post = state.posts[index];
              return _PostListTile(
                post: post,
                onTap: () => _navigateToDetail(context, post.id),
              );
            },
          ),
          if (state.isListLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  void _navigateToDetail(BuildContext context, int postId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: postId),
      ),
    );
  }
}

class _PostListTile extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;

  const _PostListTile({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Text('${post.id}')),
      title: Text(
        post.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        post.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}
