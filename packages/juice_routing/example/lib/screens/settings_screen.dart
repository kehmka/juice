import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

import '../auth_bloc.dart';

class SettingsScreen extends StatelessWidget {
  final String? section;

  const SettingsScreen({
    super.key,
    this.section,
  });

  @override
  Widget build(BuildContext context) {
    final routingBloc = BlocScope.get<RoutingBloc>();
    final authBloc = BlocScope.get<AuthBloc>();

    return Scaffold(
      appBar: AppBar(
        title: Text(section != null ? '${section!.toUpperCase()} Settings' : 'Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => routingBloc.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current section indicator
            if (section != null)
              Card(
                color: Colors.deepPurple[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_open, color: Colors.deepPurple),
                      const SizedBox(width: 12),
                      Text(
                        'Viewing: /settings/$section',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Nested routes demo
            const Text(
              'Nested Routes Demo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'These demonstrate nested route configuration.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            _SettingsTile(
              title: 'Account Settings',
              subtitle: '/settings/account',
              icon: Icons.person_outline,
              isSelected: section == 'account',
              onTap: () => routingBloc.navigate('/settings/account'),
            ),
            _SettingsTile(
              title: 'Privacy Settings',
              subtitle: '/settings/privacy',
              icon: Icons.lock_outline,
              isSelected: section == 'privacy',
              onTap: () => routingBloc.navigate('/settings/privacy'),
            ),
            _SettingsTile(
              title: 'Main Settings',
              subtitle: '/settings',
              icon: Icons.settings,
              isSelected: section == null,
              onTap: () => routingBloc.navigate('/settings'),
            ),

            const Divider(height: 32),

            // Stack info
            StreamBuilder(
              stream: routingBloc.stream,
              builder: (context, snapshot) {
                final stack = routingBloc.state.stack;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Stack',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ...stack.asMap().entries.map((entry) {
                          final index = entry.key;
                          final stackEntry = entry.value;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '${index + 1}. ${stackEntry.path}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: index == stack.length - 1
                                    ? Colors.deepPurple
                                    : Colors.grey,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () => routingBloc.popToRoot(),
                  icon: const Icon(Icons.home),
                  label: const Text('Pop to Root'),
                ),
                TextButton.icon(
                  onPressed: () {
                    authBloc.logout();
                    routingBloc.resetStack('/');
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout & Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isSelected ? Colors.deepPurple[50] : null,
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? Colors.deepPurple : null,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        trailing: isSelected
            ? const Icon(Icons.check, color: Colors.deepPurple)
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
