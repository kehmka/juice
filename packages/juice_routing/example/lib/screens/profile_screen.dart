import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

import '../auth_bloc.dart';

class ProfileScreen extends StatelessWidget {
  final String userId;

  const ProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final routingBloc = BlocScope.get<RoutingBloc>();
    final authBloc = BlocScope.get<AuthBloc>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Profile: $userId'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => routingBloc.pop(),
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
            StreamBuilder(
              stream: authBloc.stream,
              builder: (context, snapshot) {
                return Text(
                  'Logged in as: ${authBloc.state.username ?? "unknown"}',
                  style: const TextStyle(color: Colors.grey),
                );
              },
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
                          onPressed: () => routingBloc.navigate('/profile/1'),
                        ),
                        ActionChip(
                          label: const Text('User 42'),
                          onPressed: () => routingBloc.navigate('/profile/42'),
                        ),
                        ActionChip(
                          label: const Text('User ABC'),
                          onPressed: () => routingBloc.navigate('/profile/ABC'),
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
                              routingBloc.navigate('/profile/999', replace: true),
                          child: const Text('Replace with 999'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => routingBloc.navigate('/settings'),
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
                  onPressed: () => routingBloc.popToRoot(),
                  icon: const Icon(Icons.home),
                  label: const Text('Pop to Root'),
                ),
                TextButton.icon(
                  onPressed: () => authBloc.logout(),
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
