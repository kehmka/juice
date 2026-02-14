import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

import '../auth_bloc.dart';

class ProfileScreen extends StatelessJuiceWidget2<RoutingBloc, AuthBloc> {
  final String userId;

  ProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile: $userId'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => bloc1.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 50,
              child: Icon(Icons.person, size: 50),
            ),
            const SizedBox(height: 16),
            Text(
              'User ID: $userId',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Logged in as: ${bloc2.state.username ?? "unknown"}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),

            // Demo: navigate to different profile
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Route Parameters Demo',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The userId is extracted from /profile/:userId',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('User 1'),
                          onPressed: () => bloc1.navigate('/profile/1'),
                        ),
                        ActionChip(
                          label: const Text('User 42'),
                          onPressed: () => bloc1.navigate('/profile/42'),
                        ),
                        ActionChip(
                          label: const Text('User ABC'),
                          onPressed: () => bloc1.navigate('/profile/ABC'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Demo: replace current route
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Replace vs Push',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Replace swaps the current route without adding to stack.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: () =>
                              bloc1.navigate('/profile/999', replace: true),
                          child: const Text('Replace with 999'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => bloc1.navigate('/settings'),
                          child: const Text('Push Settings'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Navigation buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () => bloc1.popToRoot(),
                  icon: const Icon(Icons.home),
                  label: const Text('Pop to Root'),
                ),
                TextButton.icon(
                  onPressed: () => bloc2.logout(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
