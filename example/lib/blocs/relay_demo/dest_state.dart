import 'package:juice/juice.dart';

/// A log entry: one event a reaction sent the destination.
class ReactionLogEntry {
  /// The form of the reaction that sent it.
  static const changes = 'changes';
  static const becomes = 'becomes';

  final String message;
  final String form; // [changes] or [becomes]
  final DateTime timestamp;

  ReactionLogEntry({
    required this.message,
    required this.form,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => '[$form] $message';
}

/// State for the destination bloc: a log of what its reactions sent it.
class DestState extends BlocState {
  final List<ReactionLogEntry> log;
  final int changesCount;
  final int becomesCount;

  DestState({
    this.log = const [],
    this.changesCount = 0,
    this.becomesCount = 0,
  });

  DestState copyWith({
    List<ReactionLogEntry>? log,
    int? changesCount,
    int? becomesCount,
  }) {
    return DestState(
      log: log ?? this.log,
      changesCount: changesCount ?? this.changesCount,
      becomesCount: becomesCount ?? this.becomesCount,
    );
  }

  /// Add a new log entry
  DestState addLogEntry(ReactionLogEntry entry) {
    return copyWith(
      log: [...log, entry],
      changesCount: entry.form == ReactionLogEntry.changes
          ? changesCount + 1
          : changesCount,
      becomesCount: entry.form == ReactionLogEntry.becomes
          ? becomesCount + 1
          : becomesCount,
    );
  }

  /// Clear the log
  DestState clearLog() {
    return DestState();
  }
}
