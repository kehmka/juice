import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';

/// A card showing a live log of StorageBloc events.
///
/// Subscribes to the bloc's stream and displays each status change
/// with timestamp, status type, event type, and rebuild groups.
class EventLogCard extends StatefulWidget {
  const EventLogCard({super.key});

  @override
  State<EventLogCard> createState() => _EventLogCardState();
}

class _EventLogCardState extends State<EventLogCard> {
  StreamSubscription<StreamStatus<StorageState>>? _sub;
  final _lines = <_LogLine>[];
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final bloc = BlocScope.get<StorageBloc>();

    _sub = bloc.stream.listen((status) {
      final event = status.event;
      final groups = event?.groupsToRebuild?.join(', ') ?? '*';
      final eventType = event?.runtimeType.toString() ?? 'none';

      // Determine status type name
      final statusType = switch (status) {
        UpdatingStatus() => 'Updating',
        WaitingStatus() => 'Waiting',
        FailureStatus() => 'Failure',
        CancelingStatus() => 'Canceling',
        _ => status.runtimeType.toString(),
      };

      final line = _LogLine(
        time: DateTime.now(),
        statusType: statusType,
        eventType: eventType,
        groups: groups,
        isError: status is FailureStatus,
      );

      setState(() {
        _lines.insert(0, line);
        // Keep max 100 lines
        if (_lines.length > 100) {
          _lines.removeLast();
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.list_alt, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Event Log',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  '${_lines.length} events',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Clear log',
                  onPressed: () => setState(() => _lines.clear()),
                  icon: const Icon(Icons.clear_all, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const Divider(),
            Container(
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: _lines.isEmpty
                  ? Center(
                      child: Text(
                        'No events yet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: _lines.length,
                      itemBuilder: (_, i) => _LogLineWidget(line: _lines[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogLine {
  final DateTime time;
  final String statusType;
  final String eventType;
  final String groups;
  final bool isError;

  _LogLine({
    required this.time,
    required this.statusType,
    required this.eventType,
    required this.groups,
    this.isError = false,
  });

  String get timeStr => '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}

class _LogLineWidget extends StatelessWidget {
  const _LogLineWidget({required this.line});

  final _LogLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Color based on status type
    final statusColor = switch (line.statusType) {
      'Updating' => Colors.green,
      'Waiting' => Colors.orange,
      'Failure' => Colors.red,
      'Canceling' => Colors.grey,
      _ => theme.colorScheme.onSurface,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            '[${line.timeStr}]',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(width: 6),
          // Status type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: statusColor.withValues(alpha: 0.2),
            ),
            child: Text(
              line.statusType,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Event info
          Expanded(
            child: Text(
              '${line.eventType} → ${line.groups}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: line.isError ? Colors.red : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
