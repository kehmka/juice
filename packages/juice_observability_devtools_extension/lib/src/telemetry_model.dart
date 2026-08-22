import 'package:flutter/foundation.dart';

/// One `juice:<type>` event as received from the VM.
class JuiceEvent {
  JuiceEvent({required this.seq, required this.at, required this.kind, required this.data});

  /// Arrival order — the timeline key (VM timestamps are coarse and can tie).
  final int seq;
  final DateTime at;

  /// The `type` discriminator without the `juice:` prefix.
  final String kind;
  final Map<String, Object?> data;

  String get who =>
      (data['useCase'] ?? data['bloc'] ?? data['event'] ?? '').toString();
  String get message => (data['message'] ?? '').toString();
  int? get executionId => data['executionId'] is int ? data['executionId'] as int : null;
  int? get elapsedMicros => data['elapsedMicros'] is int ? data['elapsedMicros'] as int : null;

  bool get isProblem => const {
        'use_case_error',
        'bloc_error',
        'error_handler_error',
        'error',
        'unhandled_event',
        'leak_detection',
      }.contains(kind);
}

/// A use-case execution paired by `executionId`: start → completed|error.
class JuiceSpan {
  JuiceSpan({required this.executionId, required this.useCase, required this.event, required this.startedAt});
  final int executionId;
  final String useCase;
  final String event;
  final DateTime startedAt;
  int? elapsedMicros;
  bool failed = false;
  bool get open => elapsedMicros == null;
}

/// What the panel knows about one bloc, from emissions + lifecycle entries.
class JuiceBlocInfo {
  JuiceBlocInfo(this.name);
  final String name;
  int emissions = 0;
  String? lastState;
  String? lastStatus;
  String? lastGroups;
  String? lastEvent;
  DateTime? lastAt;
  bool closed = false;
}

/// The extension's model — pure, so the whole panel logic is unit-testable
/// without a VM. [TelemetryStore] (telemetry_store.dart) subclasses this and
/// adds the live VM wiring; the split exists because `devtools_extensions`
/// is web-only (`dart:js_interop`) and would drag every test onto Chrome.
class TelemetryModel extends ChangeNotifier {
  static const int maxEvents = 2000;

  final List<JuiceEvent> events = [];
  final Map<int, JuiceSpan> spans = {};
  final Map<String, JuiceBlocInfo> blocs = {};
  int _seq = 0;

  int get problemCount => events.where((e) => e.isProblem).length;

  /// Pure ingestion — the whole model derives from here.
  void ingest(String kind, Map<String, Object?> data, {DateTime? at}) {
    final ev = JuiceEvent(seq: _seq++, at: at ?? DateTime.now(), kind: kind, data: data);
    events.add(ev);
    if (events.length > maxEvents) events.removeAt(0);

    switch (kind) {
      case 'use_case_execution':
        final id = ev.executionId;
        if (id != null) {
          spans[id] = JuiceSpan(
            executionId: id,
            useCase: '${data['useCase'] ?? ''}',
            event: '${data['event'] ?? ''}',
            startedAt: ev.at,
          );
        }
      case 'use_case_completed':
        final s = ev.executionId == null ? null : spans[ev.executionId!];
        if (s != null) s.elapsedMicros = ev.elapsedMicros ?? 0;
      case 'use_case_error':
        // Two sources share this type; only the executor's span-closer
        // carries executionId (juice 1.7.0 contract).
        final s = ev.executionId == null ? null : spans[ev.executionId!];
        if (s != null) {
          s.elapsedMicros = ev.elapsedMicros ?? 0;
          s.failed = true;
        }
      case 'state_emission':
      case 'state_emission_skipped':
        final name = '${data['bloc'] ?? 'unknown'}';
        final b = blocs.putIfAbsent(name, () => JuiceBlocInfo(name));
        if (kind == 'state_emission') b.emissions++;
        b
          ..lastState = data['state']?.toString()
          ..lastStatus = data['status']?.toString()
          ..lastGroups = data['groups']?.toString()
          ..lastEvent = data['event']?.toString()
          ..lastAt = ev.at;
      case 'bloc_lifecycle':
        final name = '${data['bloc'] ?? 'unknown'}';
        final b = blocs.putIfAbsent(name, () => JuiceBlocInfo(name));
        if ('${data['action']}' == 'close') b.closed = true;
        b.lastAt = ev.at;
    }
    notifyListeners();
  }

  void clear() {
    events.clear();
    spans.clear();
    blocs.clear();
    notifyListeners();
  }
}
