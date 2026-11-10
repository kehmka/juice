import 'package:juice/juice.dart';
import '../relay_demo.dart';

/// Demo page showing reactions in action.
///
/// DestBloc follows SourceBloc with three reactions it attaches in its own
/// constructor (see dest_bloc.dart):
/// - `changes` on the counter;
/// - `becomes` busy;
/// - `becomes` failed.
///
/// Nothing is wired here: the page only shows the two blocs.
class RelayDemoPage extends StatelessWidget {
  const RelayDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reactions Demo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Explanation card
            Card(
              color: Colors.blue.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How Reactions Work',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'DestBloc follows SourceBloc with reactions it owns:\n\n'
                      '• changes - the counter is no longer what it was\n'
                      '• becomes - the source became busy, or got an error\n\n'
                      'A reaction sees state, so the source carries "busy" and "error" in its state. '
                      'Watch the log to see which actions each reaction answers!',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Source Bloc Card
            SourceBlocCard(),
            const SizedBox(height: 16),

            // Destination Bloc Card (Event Log)
            DestBlocCard(),
          ],
        ),
      ),
    );
  }
}

/// Card showing the source bloc state and controls
class SourceBlocCard extends StatelessJuiceWidget<SourceBloc> {
  SourceBlocCard({super.key, super.groups = const {'source'}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final isWaiting = status is WaitingStatus;
    final isFailure = status is FailureStatus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.source, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Source Bloc',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (isWaiting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (isFailure) const Icon(Icons.error, color: Colors.red),
              ],
            ),
            const Divider(),

            // Counter display
            Center(
              child: Text(
                '${bloc.state.counter}',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: isFailure ? Colors.red : Colors.blue,
                ),
              ),
            ),

            if (bloc.state.errorMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  bloc.state.errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            const SizedBox(height: 16),

            // Basic controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: isWaiting
                      ? null
                      : () => bloc.send(DecrementSourceEvent()),
                  icon: const Icon(Icons.remove),
                  label: const Text('−1'),
                ),
                ElevatedButton.icon(
                  onPressed: isWaiting
                      ? null
                      : () => bloc.send(IncrementSourceEvent()),
                  icon: const Icon(Icons.add),
                  label: const Text('+1'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Status controls
            const Text(
              'Test Status Types:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      isWaiting ? null : () => bloc.send(SimulateAsyncEvent()),
                  icon: const Icon(Icons.hourglass_empty),
                  label: const Text('Async (+10)'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      isWaiting ? null : () => bloc.send(SimulateErrorEvent()),
                  icon: const Icon(Icons.error_outline),
                  label: const Text('Error'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      isWaiting ? null : () => bloc.send(ResetSourceEvent()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Card showing the destination bloc log
class DestBlocCard extends StatelessJuiceWidget<DestBloc> {
  DestBlocCard({super.key, super.groups = const {'dest'}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.list_alt, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  'Destination Bloc (Event Log)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => bloc.send(ClearLogEvent()),
                  tooltip: 'Clear log',
                ),
              ],
            ),
            const Divider(),

            // Stats
            Row(
              children: [
                _StatChip(
                  label: 'changes',
                  count: bloc.state.changesCount,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: 'becomes',
                  count: bloc.state.becomesCount,
                  color: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Log entries
            if (bloc.state.log.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No events yet.\nTry changing the counter above!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  reverse: true, // Show newest at top
                  itemCount: bloc.state.log.length,
                  itemBuilder: (context, index) {
                    final entry =
                        bloc.state.log[bloc.state.log.length - 1 - index];
                    return _LogEntryTile(entry: entry);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        child: Text(
          '$count',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.1),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final ReactionLogEntry entry;

  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isChanges = entry.form == ReactionLogEntry.changes;
    final color = isChanges ? Colors.blue : Colors.orange;
    final icon = isChanges ? Icons.sync_alt : Icons.stream;

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(entry.message),
      subtitle: Text(
        '${entry.form} • ${_formatTime(entry.timestamp)}',
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
