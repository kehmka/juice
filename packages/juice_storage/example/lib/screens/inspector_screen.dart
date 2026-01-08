// ignore_for_file: must_be_immutable

import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';

import '../widgets/event_log.dart';

/// Inspector screen showing StorageState, cache stats, and live event log.
///
/// Demonstrates proper Juice patterns:
/// - [StatelessJuiceWidget] observes [StorageBloc]
/// - Targeted rebuild groups for storage updates
class InspectorScreen extends StatelessJuiceWidget<StorageBloc> {
  InspectorScreen({super.key})
      : super(
          groups: const {
            'storage:init',
            'storage:prefs',
            'storage:hive',
            'storage:sqlite',
            'storage:secure',
          },
        );

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final s = bloc.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspector'),
        actions: [
          IconButton(
            tooltip: 'Clear all storage',
            onPressed: s.isInitialized
                ? () => _confirmClearAll(context)
                : null,
            icon: const Icon(Icons.delete_forever),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Storage State Card
          _SectionCard(
            title: 'Storage State',
            icon: Icons.storage,
            children: [
              _InfoRow('isInitialized', s.isInitialized.toString()),
              _InfoRow(
                  'secureStorageAvailable', s.secureStorageAvailable.toString()),
              _InfoRow(
                'Hive boxes',
                s.hiveBoxes.isEmpty
                    ? 'none'
                    : s.hiveBoxes.entries
                        .map((e) => '${e.key}(${e.value.entryCount})')
                        .join(', '),
              ),
              _InfoRow(
                'SQLite tables',
                s.sqliteTables.isEmpty
                    ? 'none'
                    : s.sqliteTables.entries
                        .map((e) => '${e.key}(${e.value.rowCount})')
                        .join(', '),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Backend Status Card
          _SectionCard(
            title: 'Backend Status',
            icon: Icons.check_circle_outline,
            children: [
              _StatusRow('Hive', s.backendStatus.hive),
              _StatusRow('Prefs', s.backendStatus.prefs),
              _StatusRow('SQLite', s.backendStatus.sqlite),
              _StatusRow('Secure', s.backendStatus.secure),
            ],
          ),
          const SizedBox(height: 12),

          // Cache Stats Card
          _SectionCard(
            title: 'Cache Stats',
            icon: Icons.timer,
            children: [
              _InfoRow('Metadata entries', s.cacheStats.metadataCount.toString()),
              _InfoRow('Expired entries', s.cacheStats.expiredCount.toString()),
              _InfoRow(
                'Last cleanup',
                s.cacheStats.lastCleanupAt == null
                    ? 'never'
                    : _formatTime(s.cacheStats.lastCleanupAt!),
              ),
              _InfoRow(
                'Last cleanup removed',
                s.cacheStats.lastCleanupCleanedCount.toString(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Last Error Card (if any)
          if (s.lastError != null) ...[
            _SectionCard(
              title: 'Last Error',
              icon: Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              children: [
                _InfoRow('Type', s.lastError!.type.name),
                _InfoRow('Message', s.lastError!.message),
                if (s.lastError!.storageKey != null)
                  _InfoRow('Key', s.lastError!.storageKey!),
                _InfoRow('Time', _formatTime(s.lastError!.timestamp)),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Event Log Card
          const EventLogCard(),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Storage?'),
        content: const Text(
          'This will delete all data from Hive, SharedPreferences, '
          'Secure Storage, and SQLite. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await bloc.clearAll();
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.color,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color,
                      ),
                ),
              ],
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(this.label, this.state);

  final String label;
  final BackendState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (state) {
      BackendState.ready => (Icons.check_circle, Colors.green),
      BackendState.initializing => (Icons.hourglass_empty, Colors.orange),
      BackendState.error => (Icons.error, Colors.red),
      BackendState.uninitialized => (Icons.circle_outlined, Colors.grey),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            state.name,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
