import 'package:flutter/material.dart';

import 'telemetry_store.dart';

bool _hit(String filter, Iterable<String?> fields) {
  if (filter.isEmpty) return true;
  final f = filter.toLowerCase();
  return fields.any((s) => (s ?? '').toLowerCase().contains(f));
}

String _hms(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}.${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';

String _ms(int micros) => '${(micros / 1000).toStringAsFixed(1)} ms';

Color _kindColor(BuildContext context, String kind) {
  final s = Theme.of(context).colorScheme;
  return switch (kind) {
    'use_case_execution' => s.primary,
    'use_case_completed' => s.tertiary,
    'state_emission' => s.secondary,
    'state_emission_skipped' => s.outline,
    'bloc_lifecycle' => s.outline,
    'event_subscription' => s.outline,
    _ => s.error,
  };
}

/// Every event, newest at the bottom — the framework narrating itself.
class TimelineView extends StatelessWidget {
  const TimelineView({super.key, required this.store, required this.filter});
  final TelemetryStore store;
  final String filter;

  @override
  Widget build(BuildContext context) {
    final rows = store.events
        .where((e) => _hit(filter, [e.kind, e.who, e.message]))
        .toList();
    if (rows.isEmpty) return const _Empty('no events yet');
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final e = rows[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 84, child: Text(_hms(e.at), style: mono)),
            SizedBox(
              width: 190,
              child: Text(e.kind,
                  style: mono?.copyWith(color: _kindColor(context, e.kind))),
            ),
            SizedBox(width: 220, child: Text(e.who, style: mono, overflow: TextOverflow.ellipsis)),
            if (e.executionId != null)
              SizedBox(width: 60, child: Text('#${e.executionId}', style: mono)),
            if (e.elapsedMicros != null)
              SizedBox(width: 80, child: Text(_ms(e.elapsedMicros!), style: mono)),
            Expanded(
              child: Text(
                e.kind == 'state_emission' ? 'groups ${e.data['groups'] ?? ''}' : e.message,
                style: mono,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// Use-case executions paired by executionId — durations you can trust,
/// including overlapping same-type events under `concurrent`.
class SpansView extends StatelessWidget {
  const SpansView({super.key, required this.store, required this.filter});
  final TelemetryStore store;
  final String filter;

  @override
  Widget build(BuildContext context) {
    final rows = store.spans.values
        .where((s) => _hit(filter, [s.useCase, s.event]))
        .toList()
      ..sort((a, b) => b.executionId.compareTo(a.executionId));
    if (rows.isEmpty) return const _Empty('no use-case executions yet');
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final s = rows[i];
        final color = s.open
            ? scheme.primary
            : s.failed
                ? scheme.error
                : scheme.tertiary;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(children: [
            SizedBox(width: 60, child: Text('#${s.executionId}', style: mono)),
            SizedBox(width: 84, child: Text(_hms(s.startedAt), style: mono)),
            SizedBox(width: 240, child: Text(s.useCase, style: mono, overflow: TextOverflow.ellipsis)),
            SizedBox(width: 200, child: Text(s.event, style: mono, overflow: TextOverflow.ellipsis)),
            SizedBox(
              width: 90,
              child: Text(
                s.open ? 'running…' : _ms(s.elapsedMicros!),
                style: mono?.copyWith(color: color),
              ),
            ),
            if (s.failed) Icon(Icons.error_outline, size: 14, color: scheme.error),
          ]),
        );
      },
    );
  }
}

/// Per-bloc: emission count, last status/state/event, and THE GROUPS the
/// last emission targeted — the rebuild inspector. Groups are Juice's
/// explicit invalidation vocabulary, which is exactly why this view can
/// say *why* a widget rebuilt.
class BlocsView extends StatelessWidget {
  const BlocsView({super.key, required this.store, required this.filter});
  final TelemetryStore store;
  final String filter;

  @override
  Widget build(BuildContext context) {
    final rows = store.blocs.values
        .where((b) => _hit(filter, [b.name, b.lastEvent, b.lastGroups]))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (rows.isEmpty) return const _Empty('no bloc activity yet');
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final b = rows[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(b.name, style: theme.textTheme.titleSmall),
                const SizedBox(width: 10),
                Text('${b.emissions} emissions', style: mono),
                if (b.closed) ...[
                  const SizedBox(width: 10),
                  Text('closed', style: mono?.copyWith(color: theme.disabledColor)),
                ],
                const Spacer(),
                if (b.lastAt != null) Text(_hms(b.lastAt!), style: mono),
              ]),
              const SizedBox(height: 4),
              if (b.lastGroups != null) Text('rebuilt groups: ${b.lastGroups}', style: mono),
              if (b.lastEvent != null) Text('last event: ${b.lastEvent} (${b.lastStatus})', style: mono),
              if (b.lastState != null)
                Text('state: ${b.lastState}', style: mono, maxLines: 4, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
      },
    );
  }
}

/// Errors, unhandled events, and leak detections — the entries that
/// deserve a tab of their own.
class ProblemsView extends StatelessWidget {
  const ProblemsView({super.key, required this.store, required this.filter});
  final TelemetryStore store;
  final String filter;

  @override
  Widget build(BuildContext context) {
    final rows = store.events
        .where((e) => e.isProblem && _hit(filter, [e.kind, e.who, e.message]))
        .toList()
        .reversed
        .toList();
    if (rows.isEmpty) return const _Empty('no problems — good');
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final e = rows[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Text(e.kind, style: mono?.copyWith(color: theme.colorScheme.error)),
                const SizedBox(width: 10),
                Text(e.who, style: mono),
                const Spacer(),
                Text(_hms(e.at), style: mono),
              ]),
              if (e.message.isNotEmpty) Text(e.message, style: mono),
              if (e.data['error'] != null) Text('${e.data['error']}', style: mono, maxLines: 3),
              if (e.data['stackTrace'] != null)
                Text('${e.data['stackTrace']}', style: mono, maxLines: 6, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Center(child: Text(text, style: Theme.of(context).textTheme.bodyMedium));
}
