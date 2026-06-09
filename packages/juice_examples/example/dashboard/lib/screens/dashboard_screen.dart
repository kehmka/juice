import 'package:juice/juice.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_routing/juice_routing.dart';
import '../blocs/dashboard_bloc.dart';
import '../blocs/dashboard_state.dart';
import '../blocs/dashboard_events.dart';
import '../models/user_activity.dart';

class DashboardScreen extends StatelessJuiceWidget<DashboardBloc> {
  DashboardScreen({super.key})
      : super(groups: const {'dashboard:stats', 'dashboard:activity'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;
    final authBloc = BlocScope.get<AuthBloc>();
    final authState = authBloc.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          if (authState.user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(authState.user!.displayName ?? ''),
                avatar: const Icon(Icons.person, size: 18),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => bloc.send(RefreshStatsEvent()),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              authBloc.logout();
              final routingBloc = BlocScope.get<RoutingBloc>();
              routingBloc.navigate('/login');
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context, authState),
      body: state.isLoading || state.stats == null
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(context, state),
    );
  }

  Widget _buildDrawer(BuildContext context, AuthState authState) {
    final routingBloc = BlocScope.get<RoutingBloc>();
    final hasAdmin = authState.hasRole('admin');

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const CircleAvatar(radius: 24, child: Icon(Icons.person)),
                const SizedBox(height: 8),
                Text(authState.user?.displayName ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  authState.user?.roles.join(', ') ?? '',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            selected: true,
            onTap: () {
              Navigator.of(context).pop();
              routingBloc.navigate('/dashboard');
            },
          ),
          if (hasAdmin) ...[
            ListTile(
              leading: const Icon(Icons.analytics),
              title: const Text('Analytics'),
              onTap: () {
                Navigator.of(context).pop();
                routingBloc.navigate('/analytics');
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Users'),
              onTap: () {
                Navigator.of(context).pop();
                routingBloc.navigate('/users');
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.of(context).pop();
              routingBloc.navigate('/settings');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, DashboardState state) {
    final stats = state.stats!;
    return RefreshIndicator(
      onRefresh: () async {
        bloc.send(RefreshStatsEvent());
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Stats cards
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(
                title: 'Total Users',
                value: '${stats.totalUsers}',
                icon: Icons.people,
                color: Colors.blue,
              ),
              _StatCard(
                title: 'Revenue',
                value: '\$${stats.revenue.toStringAsFixed(0)}',
                icon: Icons.attach_money,
                color: Colors.green,
              ),
              _StatCard(
                title: 'Orders',
                value: '${stats.orders}',
                icon: Icons.shopping_bag,
                color: Colors.orange,
              ),
              _StatCard(
                title: 'Conversion',
                value: '${stats.conversionRate.toStringAsFixed(1)}%',
                icon: Icons.trending_up,
                color: Colors.purple,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Recent activity
          Text('Recent Activity',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...state.recentActivity.map(_buildActivityTile),
        ],
      ),
    );
  }

  Widget _buildActivityTile(UserActivity activity) {
    final diff = DateTime.now().difference(activity.timestamp);
    String timeAgo;
    if (diff.inMinutes < 60) {
      timeAgo = '${diff.inMinutes}m ago';
    } else {
      timeAgo = '${diff.inHours}h ago';
    }

    return ListTile(
      leading: CircleAvatar(child: Text(activity.userName[0])),
      title: Text(activity.userName),
      subtitle: Text(activity.action),
      trailing: Text(timeAgo, style: TextStyle(color: Colors.grey[600])),
    );
  }

  @override
  Widget close(BuildContext context) => const SizedBox.shrink();
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(title, style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }
}
