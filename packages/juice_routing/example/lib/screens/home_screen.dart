import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

import '../auth_bloc.dart';

class HomeScreen extends StatelessJuiceWidget2<RoutingBloc, AuthBloc> {
  HomeScreen({super.key});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (bloc2.state.isLoggedIn)
            TextButton.icon(
              onPressed: () => bloc2.logout(),
              icon: const Icon(Icons.logout),
              label: Text(bloc2.state.username ?? 'Logout'),
            )
          else
            TextButton.icon(
              onPressed: () => bloc1.navigate('/login'),
              icon: const Icon(Icons.login),
              label: const Text('Login'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'juice_routing Demo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Demonstrating declarative, state-driven navigation.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Navigation demos
            _NavigationCard(
              title: 'Navigation Playground',
              subtitle: 'Try push, pop, replace, reset and see the stack update live.',
              icon: Icons.science_outlined,
              color: Colors.teal,
              onTap: () => bloc1.navigate('/playground/1'),
            ),
            const SizedBox(height: 12),

            _NavigationCard(
              title: 'Aviator Demo',
              subtitle: 'Shows loose coupling between use cases and navigation.',
              icon: Icons.flight_takeoff,
              onTap: () => bloc1.navigate('/aviator-demo'),
            ),
            const SizedBox(height: 12),

            _NavigationCard(
              title: 'Profile (Protected)',
              subtitle: 'Requires authentication. Try navigating without logging in.',
              icon: Icons.person,
              onTap: () => bloc1.navigate('/profile/123'),
            ),
            const SizedBox(height: 12),

            _NavigationCard(
              title: 'Settings (Protected)',
              subtitle: 'Nested routes with /settings/account and /settings/privacy.',
              icon: Icons.settings,
              onTap: () => bloc1.navigate('/settings'),
            ),
            const SizedBox(height: 12),

            _NavigationCard(
              title: 'Admin Panel (Role Protected)',
              subtitle: 'Requires admin role. Try with and without admin login.',
              icon: Icons.admin_panel_settings,
              color: Colors.deepPurple,
              onTap: () => bloc1.navigate('/admin'),
            ),
            const SizedBox(height: 12),

            _NavigationCard(
              title: 'Unknown Route',
              subtitle: 'Tests the 404 not found handler.',
              icon: Icons.error_outline,
              onTap: () => bloc1.navigate('/this-does-not-exist'),
            ),

            const SizedBox(height: 24),

            // Current state display
            _buildCurrentStateCard(),

            const SizedBox(height: 16),

            // Navigation stack
            _buildNavigationStackCard(),

            const SizedBox(height: 16),

            // Full history widget
            _buildHistoryWidget(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStateCard() {
    final state = bloc1.state;
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Text(
                  'Current State',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _InfoRow('Current Path', state.currentPath ?? 'none'),
            _InfoRow('Stack Depth', '${state.stackDepth}'),
            _InfoRow('Can Pop', state.canPop ? 'Yes' : 'No'),
            _InfoRow('Is Navigating', state.isNavigating ? 'Yes' : 'No'),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${state.error.runtimeType}',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (state.error is RedirectLoopError)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 24),
                          child: Text(
                            (state.error as RedirectLoopError)
                                .redirectChain
                                .join(' \u2192 '),
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationStackCard() {
    final stack = bloc1.state.stack;
    return Card(
      color: Colors.purple[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.layers, color: Colors.purple, size: 20),
                SizedBox(width: 8),
                Text(
                  'Navigation Stack',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (stack.isEmpty)
              const Text('Stack is empty', style: TextStyle(color: Colors.grey))
            else
              ...stack.reversed.toList().asMap().entries.map((entry) {
                final index = stack.length - 1 - entry.key;
                final stackEntry = entry.value;
                final isTop = index == stack.length - 1;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isTop ? Colors.purple[100] : Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isTop ? Colors.purple : Colors.grey[300]!,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isTop ? Colors.purple : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stackEntry.path,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isTop)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'TOP',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryWidget() {
    final history = bloc1.state.history;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Navigation History',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${history.length} / 50 entries',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap any entry to navigate to that route',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
            const SizedBox(height: 12),
            if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No navigation history yet.\nTry navigating to different screens!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              // Show history in reverse order (most recent first)
              ...history.reversed.toList().asMap().entries.map((entry) {
                final index = entry.key;
                final historyEntry = entry.value;
                final typeColor = _getTypeColor(historyEntry.type);
                final isLatest = index == 0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isLatest ? Colors.grey[100] : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        // Navigate to this path
                        bloc1.navigate(historyEntry.path);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isLatest ? Colors.grey[400]! : Colors.grey[200]!,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Type indicator
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _getTypeIcon(historyEntry.type),
                                color: typeColor,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Path and details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          historyEntry.path,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (isLatest)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[700],
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'LATEST',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: typeColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          historyEntry.type.name.toUpperCase(),
                                          style: TextStyle(
                                            color: typeColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.access_time,
                                        size: 12,
                                        color: Colors.grey[500],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatTime(historyEntry.timestamp),
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (historyEntry.timeOnRoute != null) ...[
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.timer_outlined,
                                          size: 12,
                                          color: Colors.grey[500],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDuration(historyEntry.timeOnRoute),
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Navigate indicator
                            Icon(
                              Icons.open_in_new,
                              size: 16,
                              color: Colors.grey[400],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),

            // Legend
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Legend',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _LegendItem(
                  icon: Icons.arrow_forward,
                  color: Colors.green,
                  label: 'Push',
                ),
                _LegendItem(
                  icon: Icons.arrow_back,
                  color: Colors.orange,
                  label: 'Pop',
                ),
                _LegendItem(
                  icon: Icons.swap_horiz,
                  color: Colors.blue,
                  label: 'Replace',
                ),
                _LegendItem(
                  icon: Icons.refresh,
                  color: Colors.red,
                  label: 'Reset',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTypeIcon(NavigationType type) {
    switch (type) {
      case NavigationType.push:
        return Icons.arrow_forward;
      case NavigationType.pop:
        return Icons.arrow_back;
      case NavigationType.replace:
        return Icons.swap_horiz;
      case NavigationType.reset:
        return Icons.refresh;
    }
  }

  Color _getTypeColor(NavigationType type) {
    switch (type) {
      case NavigationType.push:
        return Colors.green;
      case NavigationType.pop:
        return Colors.orange;
      case NavigationType.replace:
        return Colors.blue;
      case NavigationType.reset:
        return Colors.red;
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '';
    if (duration.inSeconds < 1) {
      return '${duration.inMilliseconds}ms';
    } else if (duration.inMinutes < 1) {
      return '${duration.inSeconds}s';
    } else {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
  }
}

class _NavigationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  const _NavigationCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color?.withValues(alpha: 0.05),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: color),
        onTap: onTap,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _LegendItem({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 12),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
