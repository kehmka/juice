import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_auth/juice_auth.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authBloc = BlocScope.get<AuthBloc>();
    final user = authBloc.state.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Profile section
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
                const SizedBox(height: 12),
                Text(
                  user?.displayName ?? 'Unknown',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  user?.email ?? '',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: (user?.roles ?? {})
                      .map((r) => Chip(
                            label: Text(r),
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            subtitle: const Text('System default'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('Enabled'),
            trailing: Switch(value: true, onChanged: (_) {}),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Language'),
            subtitle: const Text('English'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('Dashboard v0.1.0 — Powered by Juice'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
