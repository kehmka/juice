import 'package:juice/juice.dart';
import '../blocs/profile_bloc.dart';
import '../blocs/profile_events.dart';

class ProfileScreen extends StatelessJuiceWidget<ProfileBloc> {
  final int userId;

  ProfileScreen({super.key, required this.userId})
      : super(groups: const {'profile:info'});

  @override
  void onInit() {
    bloc.send(LoadProfileEvent(userId: userId));
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    if (state.isLoading || state.profile == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final profile = state.profile!;
    return Scaffold(
      appBar: AppBar(title: Text(profile.username)),
      body: ListView(
        children: [
          // Profile header
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundImage: NetworkImage(profile.image),
                  onBackgroundImageError: (_, __) {},
                  child: profile.image.isEmpty
                      ? Text(profile.firstName[0],
                          style: const TextStyle(fontSize: 36))
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  profile.fullName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '@${profile.username}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StatColumn(
                        label: 'Posts', value: '${state.userPosts.length}'),
                    const SizedBox(width: 32),
                    const _StatColumn(label: 'Followers', value: '—'),
                    const SizedBox(width: 32),
                    const _StatColumn(label: 'Following', value: '—'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),

          // User's posts grid
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Posts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (state.userPosts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No posts yet')),
            )
          else
            ...state.userPosts.map(
              (post) => ListTile(
                title: Text(post.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(post.body,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, size: 16, color: Colors.red),
                    const SizedBox(width: 4),
                    Text('${post.likes}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget close(BuildContext context) => const SizedBox.shrink();
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;

  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ],
    );
  }
}
