import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

import '../models/post.dart';
import 'post_detail_screen.dart';

class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  List<Post> _posts = [];
  bool _isLoading = false;
  String? _error;
  CachePolicy _cachePolicy = CachePolicy.cacheFirst;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final fetchBloc = BlocScope.get<FetchBloc>();

    // Listen for completion
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
      url: '/posts',
      cachePolicy: _cachePolicy,
      ttl: const Duration(minutes: 5),
      decode: (raw) {
        final posts = Post.fromJsonList(raw as List);
        if (mounted) {
          setState(() => _posts = posts);
        }
        return posts;
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Posts'),
        actions: [
          PopupMenuButton<CachePolicy>(
            icon: const Icon(Icons.cached),
            tooltip: 'Cache Policy',
            onSelected: (policy) {
              setState(() => _cachePolicy = policy);
              _loadPosts();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: CachePolicy.cacheFirst,
                child: Row(
                  children: [
                    if (_cachePolicy == CachePolicy.cacheFirst)
                      const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    const Text('Cache First'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: CachePolicy.networkFirst,
                child: Row(
                  children: [
                    if (_cachePolicy == CachePolicy.networkFirst)
                      const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    const Text('Network First'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: CachePolicy.networkOnly,
                child: Row(
                  children: [
                    if (_cachePolicy == CachePolicy.networkOnly)
                      const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    const Text('Network Only'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: CachePolicy.cacheOnly,
                child: Row(
                  children: [
                    if (_cachePolicy == CachePolicy.cacheOnly)
                      const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    const Text('Cache Only'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: CachePolicy.staleWhileRevalidate,
                child: Row(
                  children: [
                    if (_cachePolicy == CachePolicy.staleWhileRevalidate)
                      const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    const Text('Stale While Revalidate'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPosts,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadPosts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPosts,
      child: Stack(
        children: [
          ListView.builder(
            itemCount: _posts.length,
            itemBuilder: (context, index) {
              final post = _posts[index];
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
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PostDetailScreen(postId: post.id),
                    ),
                  );
                },
              );
            },
          ),
          if (_isLoading)
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
}
