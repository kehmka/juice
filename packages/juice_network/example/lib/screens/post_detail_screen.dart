import 'package:juice/juice.dart';

import '../blocs/blocs.dart';

class PostDetailScreen extends StatelessJuiceWidget<PostsBloc> {
  final int postId;

  PostDetailScreen({super.key, required this.postId});

  @override
  void onInit() {
    bloc.send(LoadPostDetailEvent(postId));
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    // Handle deletion - navigate back
    if (state.postDeleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post deleted (simulated)')),
          );
          Navigator.pop(context);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Post #$postId'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _confirmDelete(context),
            tooltip: 'Delete',
          ),
        ],
      ),
      body: _buildBody(context, state),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      bloc.send(DeletePostEvent());
    }
  }

  Widget _buildBody(BuildContext context, PostsState state) {
    if (state.isDetailLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.detailError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(state.detailError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => bloc.send(LoadPostDetailEvent(postId)),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final post = state.selectedPost;
    if (post == null) {
      return const Center(child: Text('Post not found'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(child: Text('${post.userId}')),
                      const SizedBox(width: 12),
                      Text(
                        'User ${post.userId}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    post.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    post.body,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
