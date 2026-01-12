import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

class CoalesceScreen extends StatefulWidget {
  const CoalesceScreen({super.key});

  @override
  State<CoalesceScreen> createState() => _CoalesceScreenState();
}

class _CoalesceScreenState extends State<CoalesceScreen> {
  int _tapCount = 0;
  int _networkCalls = 0;
  int _coalescedCount = 0;
  final List<String> _logs = [];

  void _log(String message) {
    setState(() {
      _logs.insert(0, '${DateTime.now().toIso8601String().substring(11, 23)} $message');
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  void _fireRequest() {
    setState(() => _tapCount++);
    _log('Tap #$_tapCount - firing request');

    final fetchBloc = BlocScope.get<FetchBloc>();
    final coalescedBefore = fetchBloc.state.stats.coalescedCount;

    // Fire without awaiting so multiple requests can be inflight
    fetchBloc.send(GetEvent(
      url: '/posts/1',
      cachePolicy: CachePolicy.networkOnly,
      decode: (raw) => raw,
    )).then((_) {
      final stats = fetchBloc.state.stats;
      if (stats.coalescedCount > coalescedBefore) {
        setState(() => _coalescedCount = stats.coalescedCount);
        _log('Request was COALESCED (shared existing call)');
      } else {
        setState(() => _networkCalls++);
        _log('Network call completed');
      }
    });
  }

  void _fireBurst() {
    final count = 10;
    _log('Firing BURST of $count simultaneous requests...');

    final fetchBloc = BlocScope.get<FetchBloc>();
    final coalescedBefore = fetchBloc.state.stats.coalescedCount;
    final successBefore = fetchBloc.state.stats.successCount;

    // Fire all requests simultaneously (no await between them)
    final futures = <Future>[];
    for (var i = 0; i < count; i++) {
      setState(() => _tapCount++);
      futures.add(fetchBloc.send(GetEvent(
        url: '/posts/1',
        cachePolicy: CachePolicy.networkOnly,
        decode: (raw) => raw,
      )));
    }

    // Wait for all to complete, then check stats
    Future.wait(futures).then((_) {
      final stats = fetchBloc.state.stats;
      final newCoalesced = stats.coalescedCount - coalescedBefore;
      final newSuccess = stats.successCount - successBefore;

      setState(() {
        _coalescedCount = stats.coalescedCount;
        _networkCalls += newSuccess;
      });

      _log('Burst complete: $newSuccess network calls, $newCoalesced coalesced');
    });
  }

  void _reset() {
    final fetchBloc = BlocScope.get<FetchBloc>();
    fetchBloc.send(ResetStatsEvent());
    setState(() {
      _tapCount = 0;
      _networkCalls = 0;
      _coalescedCount = 0;
      _logs.clear();
    });
    _log('Stats reset');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Coalescing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reset,
            tooltip: 'Reset',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Tap the button rapidly!',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Multiple requests to the same URL will be coalesced into a single network call.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _fireRequest,
                          icon: const Icon(Icons.bolt),
                          label: const Text('Fire Request'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(150, 56),
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          onPressed: _fireBurst,
                          icon: const Icon(Icons.flash_on),
                          label: const Text('Fire Burst (10x)'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(150, 56),
                            backgroundColor: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatChip(
                          label: 'Taps',
                          value: _tapCount,
                          color: Colors.blue,
                        ),
                        _StatChip(
                          label: 'Network Calls',
                          value: _networkCalls,
                          color: Colors.green,
                        ),
                        _StatChip(
                          label: 'Coalesced',
                          value: _coalescedCount,
                          color: Colors.orange,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Event Log',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  Color color = Colors.white70;
                  if (log.contains('COALESCED')) {
                    color = Colors.orange;
                  } else if (log.contains('network call')) {
                    color = Colors.green;
                  } else if (log.contains('Response')) {
                    color = Colors.cyan;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      log,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: color,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
