import 'package:juice/juice.dart';
import '../relay_demo.dart';

/// Demo page showing StateRelay and StatusRelay in action.
///
/// This page demonstrates:
/// - StateRelay: Simple state-to-event transformation (counter changes)
/// - StatusRelay: Full status handling (updating, waiting, failure states)
class RelayDemoPage extends StatefulWidget {
  const RelayDemoPage({super.key});

  @override
  State<RelayDemoPage> createState() => _RelayDemoPageState();
}

class _RelayDemoPageState extends State<RelayDemoPage> {
  late StateRelay<SourceBloc, DestBloc, SourceState> _stateRelay;
  late StatusRelay<SourceBloc, DestBloc, SourceState> _statusRelay;

  @override
  void initState() {
    super.initState();
    _setupRelays();
  }

  void _setupRelays() {
    // StateRelay: Simple state-to-event transformation
    // Only reacts to state values, not waiting/error states
    _stateRelay = StateRelay<SourceBloc, DestBloc, SourceState>(
      toEvent: (state) => StateRelayedEvent(counter: state.counter),
      // Optional: filter to only relay when counter > 0
      // when: (state) => state.counter > 0,
    );

    // StatusRelay: Full StreamStatus handling
    // Reacts differently to updating, waiting, and failure states
    _statusRelay = StatusRelay<SourceBloc, DestBloc, SourceState>(
      toEvent: (status) => status.when(
        updating: (state, _, __) => StatusUpdatingEvent(counter: state.counter),
        waiting: (_, __, ___) => StatusWaitingEvent(),
        failure: (state, _, __) =>
            StatusFailedEvent(errorMessage: state.errorMessage),
        canceling: (_, __, ___) => StatusWaitingEvent(),
      ),
    );
  }

  @override
  void dispose() {
    _stateRelay.close();
    _statusRelay.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('StateRelay & StatusRelay Demo'),
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
                      'How Relays Work',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This demo shows two blocs connected via relays:\n\n'
                      '• StateRelay - Transforms state changes into events\n'
                      '• StatusRelay - Handles all status types (updating, waiting, failure)\n\n'
                      'Watch the log to see how each relay responds to different actions!',
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
                if (isFailure)
                  const Icon(Icons.error, color: Colors.red),
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
                  onPressed:
                      isWaiting ? null : () => bloc.send(IncrementSourceEvent()),
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
                  label: 'StateRelay',
                  count: bloc.state.stateRelayCount,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: 'StatusRelay',
                  count: bloc.state.statusRelayCount,
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
  final RelayLogEntry entry;

  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isStateRelay = entry.source == 'StateRelay';
    final color = isStateRelay ? Colors.blue : Colors.orange;
    final icon = isStateRelay ? Icons.sync_alt : Icons.stream;

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(entry.message),
      subtitle: Text(
        '${entry.source} • ${_formatTime(entry.timestamp)}',
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
