import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

import '../models/post.dart';

class PostDetailScreen extends StatefulWidget {
  final int postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Post? _post;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  Future<void> _loadPost() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final fetchBloc = BlocScope.get<FetchBloc>();

    late StreamSubscription<StreamStatus<FetchState>> sub;
    sub = fetchBloc.stream.listen((status) {
      if (status is! WaitingStatus) {
        sub.cancel();
        if (mounted) {
          setState(() {
            _isLoading = false;
            if (status is FailureStatus) {
              _error = fetchBloc.state.lastError?.toString() ?? 'Unknown error';
            }
          });
        }
      }
    });

    await fetchBloc.send(GetEvent(
      url: '/posts/${widget.postId}',
      cachePolicy: CachePolicy.cacheFirst,
      ttl: const Duration(minutes: 5),
      decode: (raw) {
        final post = Post.fromJson(raw as Map<String, dynamic>);
        if (mounted) {
          setState(() => _post = post);
        }
        return post;
      },
    ));
  }

  Future<void> _deletePost() async {
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

    if (confirm != true || !mounted) return;

    final fetchBloc = BlocScope.get<FetchBloc>();

    await fetchBloc.send(DeleteEvent(
      url: '/posts/${widget.postId}',
    ));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post deleted (simulated)')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Post #${widget.postId}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deletePost,
            tooltip: 'Delete',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadPost,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_post == null) {
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
                      CircleAvatar(child: Text('${_post!.userId}')),
                      const SizedBox(width: 12),
                      Text(
                        'User ${_post!.userId}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _post!.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _post!.body,
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
