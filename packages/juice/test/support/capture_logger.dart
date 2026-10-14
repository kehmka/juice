import 'package:juice/juice.dart';

/// Shared test fixtures: a logger that records every entry as a map, one
/// event-loop turn, and a quiet error handler.

/// Records every log entry as a map: `message`, `level`, `error` (for
/// `logError`) and the entry's context fields.
class CaptureLogger implements JuiceLogger {
  @override
  void record(JuiceTelemetry e) => entries.add({
        'message': e.message,
        'level': e.level,
        ...e.toMap(),
      });

  final entries = <Map<String, dynamic>>[];

  @override
  void log(String message,
          {Level level = Level.info, Map<String, dynamic>? context}) =>
      entries.add({'message': message, 'level': level, ...?context});

  @override
  void logError(String message, Object error, StackTrace stackTrace,
          {Map<String, dynamic>? context}) =>
      entries.add({
        'message': message,
        'error': error,
        'level': Level.error,
        ...?context,
      });

  /// The messages passed to `logError`, in order.
  List<String> get errors => [
        for (final e in entries)
          if (e['level'] == Level.error) e['message'] as String,
      ];

  /// Entries whose `type` is [type], optionally with `action` [action].
  Iterable<Map<String, dynamic>> where(String type, [String? action]) =>
      entries.where((e) =>
          e['type'] == type && (action == null || e['action'] == action));

  /// Entries whose `type` is [type].
  Iterable<Map<String, dynamic>> typed(String type) => where(type);

  /// `stream_binding` entries with `action` [action].
  Iterable<Map<String, dynamic>> bindings(String action) =>
      where('stream_binding', action);
}

/// Waits [n] event-loop turns (every pending microtask and zero-delay timer
/// runs); never a real-time sleep.
Future<void> pump([int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Swallows the default handler's print; tests assert on the bloc's own
/// `errors` or on the captured log.
final quietErrorHandler =
    BlocErrorHandler(onError: (m, {error, stackTrace}) {});
