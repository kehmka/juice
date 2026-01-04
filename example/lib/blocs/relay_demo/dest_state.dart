import 'package:juice/juice.dart';

/// A log entry for tracking relayed events
class RelayLogEntry {
  final String message;
  final String source; // 'StateRelay' or 'StatusRelay'
  final DateTime timestamp;

  RelayLogEntry({
    required this.message,
    required this.source,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => '[$source] $message';
}

/// State for the destination bloc that receives relayed events.
/// Logs all events it receives to show how relays work.
class DestState extends BlocState {
  final List<RelayLogEntry> log;
  final int stateRelayCount;
  final int statusRelayCount;

  DestState({
    this.log = const [],
    this.stateRelayCount = 0,
    this.statusRelayCount = 0,
  });

  DestState copyWith({
    List<RelayLogEntry>? log,
    int? stateRelayCount,
    int? statusRelayCount,
  }) {
    return DestState(
      log: log ?? this.log,
      stateRelayCount: stateRelayCount ?? this.stateRelayCount,
      statusRelayCount: statusRelayCount ?? this.statusRelayCount,
    );
  }

  /// Add a new log entry
  DestState addLogEntry(RelayLogEntry entry) {
    return copyWith(
      log: [...log, entry],
      stateRelayCount:
          entry.source == 'StateRelay' ? stateRelayCount + 1 : stateRelayCount,
      statusRelayCount: entry.source == 'StatusRelay'
          ? statusRelayCount + 1
          : statusRelayCount,
    );
  }

  /// Clear the log
  DestState clearLog() {
    return DestState();
  }
}
