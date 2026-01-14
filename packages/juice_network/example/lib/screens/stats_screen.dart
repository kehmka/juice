import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

class StatsScreen extends StatelessJuiceWidget<FetchBloc> {
  StatsScreen({super.key});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;
    final stats = state.stats;
    final cacheStats = state.cacheStats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Stats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              bloc.send(ResetStatsEvent());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Stats reset')),
              );
            },
            tooltip: 'Reset Stats',
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            onPressed: () {
              bloc.send(ClearCacheEvent());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared')),
              );
            },
            tooltip: 'Clear Cache',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'Request Statistics'),
          _StatsCard(
            children: [
              _StatRow('Total Requests', '${stats.totalRequests}'),
              _StatRow('Successful', '${stats.successCount}', color: Colors.green),
              _StatRow('Failed', '${stats.failureCount}', color: Colors.red),
              _StatRow('Success Rate', '${stats.successRate.toStringAsFixed(1)}%'),
              _StatRow('Retries', '${stats.retryCount}'),
              _StatRow('Coalesced', '${stats.coalescedCount}', color: Colors.orange),
            ],
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'Cache Statistics'),
          _StatsCard(
            children: [
              _StatRow('Cache Hits', '${stats.cacheHits}', color: Colors.green),
              _StatRow('Cache Misses', '${stats.cacheMisses}', color: Colors.orange),
              _StatRow('Hit Rate', '${stats.hitRate.toStringAsFixed(1)}%'),
              _StatRow('Entries', '${cacheStats.entryCount}'),
              _StatRow('Size', _formatBytes(cacheStats.totalBytes)),
            ],
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'Performance'),
          _StatsCard(
            children: [
              _StatRow('Avg Response Time', '${stats.avgResponseTimeMs.toStringAsFixed(0)} ms'),
              _StatRow('Bytes Received', _formatBytes(stats.bytesReceived)),
              _StatRow('Bytes Sent', _formatBytes(stats.bytesSent)),
            ],
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'Current State'),
          _StatsCard(
            children: [
              _StatRow('Initialized', state.isInitialized ? 'Yes' : 'No'),
              _StatRow('Inflight Requests', '${state.inflightCount}'),
              _StatRow('Active Requests', '${state.activeRequests.length}'),
              _StatRow(
                'Last Error',
                state.lastError?.toString() ?? 'None',
                color: state.lastError != null ? Colors.red : null,
              ),
            ],
          ),
          if (state.activeRequests.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionHeader(title: 'Active Requests'),
            ...state.activeRequests.entries.map((entry) {
              final reqStatus = entry.value;
              return Card(
                child: ListTile(
                  leading: Icon(
                    reqStatus.phase == RequestPhase.inflight
                        ? Icons.sync
                        : Icons.hourglass_empty,
                    color: reqStatus.phase == RequestPhase.inflight
                        ? Colors.blue
                        : Colors.grey,
                  ),
                  title: Text(
                    entry.key,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                  subtitle: Text(
                    'Phase: ${reqStatus.phase.name} | Attempt: ${reqStatus.attempt}',
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final List<Widget> children;

  const _StatsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: children),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
