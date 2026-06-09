import 'package:juice/juice.dart';
import '../blocs/feed_bloc.dart';
import '../blocs/feed_events.dart';

class PostDetailScreen extends StatelessJuiceWidget<FeedBloc> {
  PostDetailScreen({super.key}) : super(groups: const {'feed:detail'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;
    final post = state.selectedPost;

    if (post == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Post content
          Text(
            post.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(radius: 14, child: Text('U${post.userId}')),
              const SizedBox(width: 8),
              Text('User ${post.userId}',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 16),
          Text(post.body, style: const TextStyle(fontSize: 16, height: 1.5)),
          if (post.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: post.tags
                  .map((tag) => Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                onPressed: () => bloc.send(LikePostEvent(postId: post.id)),
                icon: const Icon(Icons.favorite_border, color: Colors.red),
              ),
              Text('${post.likes} likes'),
              const SizedBox(width: 16),
              const Icon(Icons.visibility, size: 18, color: Colors.grey),
              const SizedBox(width: 4),
              Text('${post.views} views'),
            ],
          ),
          const Divider(height: 32),

          // Comments section
          Text(
            'Comments (${state.selectedPostComments.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ...state.selectedPostComments.map(
            (comment) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.userName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(comment.body),
                    if (comment.likes > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${comment.likes} likes',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _AddCommentField(
            onSubmit: (text) => bloc.send(AddCommentEvent(
              postId: post.id,
              body: text,
            )),
          ),
        ],
      ),
    );
  }

  @override
  Widget close(BuildContext context) => const SizedBox.shrink();
}

class _AddCommentField extends StatefulWidget {
  final void Function(String) onSubmit;

  const _AddCommentField({required this.onSubmit});

  @override
  State<_AddCommentField> createState() => _AddCommentFieldState();
}

class _AddCommentFieldState extends State<_AddCommentField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Add a comment...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isNotEmpty) {
              widget.onSubmit(text);
              _controller.clear();
            }
          },
          icon: const Icon(Icons.send),
        ),
      ],
    );
  }
}
