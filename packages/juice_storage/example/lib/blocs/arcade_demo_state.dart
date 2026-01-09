import 'package:juice/juice.dart';

import '../demo_entry.dart';

/// State for the Arcade demo screen.
class ArcadeDemoState extends BlocState {
  const ArcadeDemoState({
    this.entries = const [],
    this.banner = 'Save an entry to get started',
    this.selectedBackend = DemoBackend.prefs,
    this.ttlSeconds = 10.0,
    this.keyText = 'myKey',
    this.valueText = '{"data": "hello"}',
    this.currentTime,
    this.isOperationInProgress = false,
    this.evictionsByBackend = const {},
  });

  /// List of demo entries (displayed in the UI).
  final List<DemoEntry> entries;

  /// Banner message showing last operation result.
  final String banner;

  /// Currently selected storage backend.
  final DemoBackend selectedBackend;

  /// TTL slider value in seconds.
  final double ttlSeconds;

  /// Key text field value.
  final String keyText;

  /// Value text field value.
  final String valueText;

  /// Current time for countdown display (null before first tick).
  final DateTime? currentTime;

  /// Whether an async operation is in progress.
  final bool isOperationInProgress;

  /// Cumulative eviction counts by backend type.
  final Map<DemoBackend, int> evictionsByBackend;

  /// Total evictions across all backends.
  int get totalEvictions => evictionsByBackend.values.fold(0, (a, b) => a + b);

  /// Formatted eviction summary for display.
  String get evictionSummary {
    if (totalEvictions == 0) return 'No evictions yet';
    final parts = <String>[];
    for (final backend in DemoBackend.values) {
      final count = evictionsByBackend[backend] ?? 0;
      if (count > 0) {
        parts.add('${backend.name}: $count');
      }
    }
    return 'Evicted $totalEvictions total (${parts.join(', ')})';
  }

  /// Whether TTL is supported for the selected backend.
  bool get ttlSupported =>
      selectedBackend == DemoBackend.prefs ||
      selectedBackend == DemoBackend.hive;

  /// Current time or fallback to now.
  DateTime get now => currentTime ?? DateTime.now();

  ArcadeDemoState copyWith({
    List<DemoEntry>? entries,
    String? banner,
    DemoBackend? selectedBackend,
    double? ttlSeconds,
    String? keyText,
    String? valueText,
    DateTime? currentTime,
    bool? isOperationInProgress,
    Map<DemoBackend, int>? evictionsByBackend,
  }) {
    return ArcadeDemoState(
      entries: entries ?? this.entries,
      banner: banner ?? this.banner,
      selectedBackend: selectedBackend ?? this.selectedBackend,
      ttlSeconds: ttlSeconds ?? this.ttlSeconds,
      keyText: keyText ?? this.keyText,
      valueText: valueText ?? this.valueText,
      currentTime: currentTime ?? this.currentTime,
      isOperationInProgress:
          isOperationInProgress ?? this.isOperationInProgress,
      evictionsByBackend: evictionsByBackend ?? this.evictionsByBackend,
    );
  }
}
