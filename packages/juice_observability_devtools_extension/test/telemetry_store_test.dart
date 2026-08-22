import 'package:flutter_test/flutter_test.dart';
import 'package:juice_observability_devtools_extension/src/telemetry_model.dart';

/// The panel's model derives entirely from [TelemetryModel.ingest], which is
/// pure — so the whole panel logic is testable without a VM connection.
void main() {
  late TelemetryModel store;
  setUp(() => store = TelemetryModel());

  test('a start/completed pair becomes one closed span with its duration', () {
    store.ingest('use_case_execution',
        {'useCase': 'LoadFoo', 'event': 'LoadFooEvent', 'executionId': 3});
    expect(store.spans[3]!.open, isTrue);
    store.ingest('use_case_completed',
        {'useCase': 'LoadFoo', 'executionId': 3, 'elapsedMicros': 4200});
    final s = store.spans[3]!;
    expect(s.open, isFalse);
    expect(s.failed, isFalse);
    expect(s.elapsedMicros, 4200);
  });

  test('the executor use_case_error closes a span as failed; the handler '
      'summary (no executionId) does not disturb spans', () {
    store.ingest('use_case_execution', {'useCase': 'Save', 'event': 'SaveEvent', 'executionId': 9});
    store.ingest('use_case_error', {'useCase': 'Save', 'executionId': 9, 'elapsedMicros': 10});
    store.ingest('use_case_error', {'bloc': 'SaveBloc', 'event': 'SaveEvent', 'state': 'S'});
    expect(store.spans[9]!.failed, isTrue);
    expect(store.spans, hasLength(1));
    expect(store.problemCount, 2, reason: 'both error entries are problems');
  });

  test('overlapping same-type executions stay distinct spans', () {
    store.ingest('use_case_execution', {'useCase': 'A', 'event': 'E', 'executionId': 1});
    store.ingest('use_case_execution', {'useCase': 'A', 'event': 'E', 'executionId': 2});
    store.ingest('use_case_completed', {'executionId': 2, 'elapsedMicros': 5});
    expect(store.spans[1]!.open, isTrue);
    expect(store.spans[2]!.open, isFalse);
  });

  test('emissions build the per-bloc view with groups, status, and state', () {
    store.ingest('state_emission', {
      'bloc': 'FooBloc', 'status': 'update', 'state': 'FooState(1)',
      'groups': '{foo:status}', 'event': 'LoadFooEvent',
    });
    store.ingest('state_emission', {
      'bloc': 'FooBloc', 'status': 'update', 'state': 'FooState(2)',
      'groups': '{foo:status, foo:list}', 'event': 'LoadFooEvent',
    });
    store.ingest('bloc_lifecycle', {'bloc': 'FooBloc', 'action': 'close'});
    final b = store.blocs['FooBloc']!;
    expect(b.emissions, 2);
    expect(b.lastGroups, '{foo:status, foo:list}');
    expect(b.lastState, 'FooState(2)');
    expect(b.closed, isTrue);
  });

  test('problems are the error kinds, unhandled events, and leaks', () {
    for (final k in ['leak_detection', 'unhandled_event', 'error', 'bloc_error']) {
      store.ingest(k, {'message': k});
    }
    store.ingest('state_emission', {'bloc': 'X'});
    expect(store.problemCount, 4);
  });

  test('the event buffer is capped', () {
    for (var i = 0; i < TelemetryModel.maxEvents + 50; i++) {
      store.ingest('bloc_lifecycle', {'bloc': 'B$i'});
    }
    expect(store.events, hasLength(TelemetryModel.maxEvents));
  });

  test('clear empties everything', () {
    store.ingest('use_case_execution', {'executionId': 1, 'useCase': 'A', 'event': 'E'});
    store.ingest('state_emission', {'bloc': 'B'});
    store.clear();
    expect(store.events, isEmpty);
    expect(store.spans, isEmpty);
    expect(store.blocs, isEmpty);
  });
}
