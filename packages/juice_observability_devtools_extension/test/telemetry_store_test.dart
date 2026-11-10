import 'package:flutter_test/flutter_test.dart';
import 'package:juice_observability_devtools_extension/src/telemetry_model.dart';

/// The panel's model derives entirely from [TelemetryModel.ingest], which is
/// pure — so the whole panel logic is testable without a VM connection.
void main() {
  late TelemetryModel store;
  setUp(() => store = TelemetryModel());

  test('a start/completed pair becomes one closed span with its duration', () {
    store.ingest('use_case_execution', {
      'useCase': 'LoadFoo',
      'event': 'LoadFooEvent',
      'executionId': 3,
    });
    expect(store.spans[3]!.open, isTrue);
    store.ingest('use_case_completed', {
      'useCase': 'LoadFoo',
      'executionId': 3,
      'elapsedMicros': 4200,
    });
    final s = store.spans[3]!;
    expect(s.open, isFalse);
    expect(s.failed, isFalse);
    expect(s.elapsedMicros, 4200);
  });

  test('the executor use_case_error closes a span as failed; the handler '
      'summary (no executionId) does not disturb spans', () {
    store.ingest('use_case_execution', {
      'useCase': 'Save',
      'event': 'SaveEvent',
      'executionId': 9,
    });
    store.ingest('use_case_error', {
      'useCase': 'Save',
      'executionId': 9,
      'elapsedMicros': 10,
    });
    store.ingest('use_case_error', {
      'bloc': 'SaveBloc',
      'event': 'SaveEvent',
      'state': 'S',
    });
    expect(store.spans[9]!.failed, isTrue);
    expect(store.spans, hasLength(1));
    expect(store.problemCount, 2, reason: 'both error entries are problems');
  });

  test('overlapping same-type executions stay distinct spans', () {
    store.ingest('use_case_execution', {
      'useCase': 'A',
      'event': 'E',
      'executionId': 1,
    });
    store.ingest('use_case_execution', {
      'useCase': 'A',
      'event': 'E',
      'executionId': 2,
    });
    store.ingest('use_case_completed', {'executionId': 2, 'elapsedMicros': 5});
    expect(store.spans[1]!.open, isTrue);
    expect(store.spans[2]!.open, isFalse);
  });

  test('emissions build the per-bloc view with groups, status, and state', () {
    store.ingest('state_emission', {
      'bloc': 'FooBloc',
      'status': 'update',
      'state': 'FooState(1)',
      'groups': '{foo:status}',
      'event': 'LoadFooEvent',
    });
    store.ingest('state_emission', {
      'bloc': 'FooBloc',
      'status': 'update',
      'state': 'FooState(2)',
      'groups': '{foo:status, foo:list}',
      'event': 'LoadFooEvent',
    });
    store.ingest('bloc_lifecycle', {'bloc': 'FooBloc', 'action': 'close'});
    final b = store.blocs['FooBloc']!;
    expect(b.emissions, 2);
    expect(b.lastGroups, '{foo:status, foo:list}');
    expect(b.lastState, 'FooState(2)');
    expect(b.closed, isTrue);
  });

  test(
    'with no level posted (juice 1.x), the 1.x error names are problems',
    () {
      for (final k in [
        'use_case_error',
        'unhandled_event',
        'error',
        'bloc_error',
        'error_handler_error',
      ]) {
        store.ingest(k, {'message': k});
      }
      store.ingest('state_emission', {'bloc': 'X'});
      expect(store.problemCount, 5);
    },
  );

  test('"Leak detection enabled" is not a problem: it is the only entry juice '
      'has ever posted as leak_detection, and it is info', () {
    store.ingest('leak_detection', {'action': 'enable', 'level': 'info'});
    store.ingest('leak_detection', {'action': 'enable'}); // 1.x: no level
    expect(store.problemCount, 0);
    expect(store.events.map((e) => e.tone), everyElement(JuiceEventTone.plain));
  });

  test('every error-level entry is a problem, by level, whatever its name', () {
    // juice 2.0.0's typed telemetry posts `level`; the new error kinds need
    // no name list here.
    for (final k in [
      'sequential_run_error',
      'supersede_error',
      'relay_error',
      'aviator_error',
      'bloc_close_error',
      'stream_binding',
      'event_subscription',
    ]) {
      store.ingest(k, {'message': k, 'level': 'error'});
    }
    store.ingest('stream_binding', {'action': 'refused', 'level': 'warning'});
    store.ingest('bloc_lifecycle', {'action': 'close', 'level': 'info'});
    expect(store.problemCount, 7);
  });

  group('the timeline tone of a row', () {
    JuiceEventTone tone(String kind, [Map<String, Object?> data = const {}]) {
      store.ingest(kind, data);
      return store.events.last.tone;
    }

    // juice 2.x's whole telemetry vocabulary as the logger posts it: wire
    // type, action, level (`JuiceTelemetryKind` in packages/juice;
    // juice_observability's own test pins that every kind posts its level).
    const vocabulary = <(String, String?, String)>[
      ('use_case_execution', null, 'info'),
      ('use_case_completed', null, 'info'),
      ('use_case_error', null, 'error'),
      ('sequential_run_error', null, 'error'),
      ('use_case_superseded', null, 'info'),
      ('event_dropped', null, 'info'),
      ('supersede_error', null, 'error'),
      ('state_emission', null, 'info'),
      ('state_emission_skipped', null, 'info'),
      ('state_emission_superseded', null, 'info'),
      ('emission_after_close', null, 'warning'),
      ('bloc_lifecycle', 'event_ignored', 'warning'),
      ('bloc_lifecycle', 'close', 'info'),
      ('bloc_lifecycle', 'register', 'info'),
      ('bloc_lifecycle', 'create', 'info'),
      ('bloc_lifecycle', 'lease_acquire', 'info'),
      ('bloc_lifecycle', 'lease_release', 'info'),
      ('bloc_lifecycle', 'lease_release_stale', 'info'),
      ('bloc_lifecycle', 'get_on_leased', 'warning'),
      ('bloc_lifecycle', 'end_feature', 'info'),
      ('bloc_lifecycle', 'end_all', 'info'),
      ('bloc_close_error', null, 'error'),
      ('bloc_error', null, 'error'),
      ('error_handler_error', null, 'error'),
      ('unhandled_event', null, 'error'),
      ('aviator_error', null, 'error'),
      ('stream_binding', 'bind', 'info'),
      ('stream_binding', 'done', 'info'),
      ('stream_binding', 'refused', 'warning'),
      ('stream_binding', 'refused', 'info'),
      ('stream_binding', 'error', 'error'),
      ('stream_binding', 'callback_error', 'error'),
      ('stream_binding', 'cancel_error', 'error'),
      ('retry_scheduled', null, 'info'),
      ('retry_exhausted', null, 'info'),
      ('retry_abandoned', null, 'info'),
      ('event_subscription', 'initialize', 'info'),
      ('event_subscription', 'trigger', 'info'),
      ('event_subscription', 'close', 'info'),
      ('event_subscription', 'error', 'error'),
      ('relay_error', null, 'error'),
      ('leak_detection', 'enable', 'info'),
    ];

    test('across the whole vocabulary: a problem exactly when the level is '
        'error, a warning exactly when it is warning', () {
      for (final (type, action, level) in vocabulary) {
        final t = tone(type, {'level': level, 'action': ?action});
        final label = '$type${action == null ? '' : ' / $action'} at $level';
        expect(t == JuiceEventTone.problem, level == 'error', reason: label);
        expect(t == JuiceEventTone.warning, level == 'warning', reason: label);
      }
    });

    test('the info entries that used to be painted as errors are calm', () {
      for (final (type, action) in const [
        ('use_case_superseded', null),
        ('state_emission_superseded', null),
        ('stream_binding', 'bind'),
        ('stream_binding', 'done'),
        ('retry_scheduled', null),
        ('retry_exhausted', null),
        ('retry_abandoned', null),
        ('leak_detection', 'enable'),
      ]) {
        expect(
          tone(type, {'level': 'info', 'action': ?action}),
          JuiceEventTone.plain,
          reason: type,
        );
      }
    });

    test('the level outranks the type: a calm type at error is a problem', () {
      expect(
        tone('stream_binding', {'level': 'error'}),
        JuiceEventTone.problem,
      );
      expect(
        tone('event_subscription', {'level': 'error'}),
        JuiceEventTone.problem,
      );
      expect(
        tone('state_emission', {'level': 'fatal'}),
        JuiceEventTone.problem,
      );
      expect(
        tone('bloc_lifecycle', {'level': 'warning'}),
        JuiceEventTone.warning,
      );
    });

    test('each calm type keeps its own tone', () {
      expect(
        tone('use_case_execution', {'level': 'info'}),
        JuiceEventTone.started,
      );
      expect(
        tone('use_case_completed', {'level': 'info'}),
        JuiceEventTone.completed,
      );
      expect(
        tone('state_emission', {'level': 'info'}),
        JuiceEventTone.emission,
      );
      for (final quiet in const [
        'state_emission_skipped',
        'bloc_lifecycle',
        'event_subscription',
        'event_dropped',
      ]) {
        expect(
          tone(quiet, {'level': 'info'}),
          JuiceEventTone.quiet,
          reason: quiet,
        );
      }
    });

    test('a type the panel has never heard of is plain, not an error', () {
      expect(tone('something_new', {'level': 'info'}), JuiceEventTone.plain);
      expect(tone('something_new', {'level': 'debug'}), JuiceEventTone.plain);
      expect(
        tone('something_new'),
        JuiceEventTone.plain,
        reason: 'no level posted, and not a 1.x error name',
      );
    });

    test('with no level posted, a 1.x error name is still a problem', () {
      expect(tone('use_case_error'), JuiceEventTone.problem);
      expect(tone('state_emission'), JuiceEventTone.emission);
    });
  });

  test('the event buffer is capped', () {
    for (var i = 0; i < TelemetryModel.maxEvents + 50; i++) {
      store.ingest('bloc_lifecycle', {'bloc': 'B$i'});
    }
    expect(store.events, hasLength(TelemetryModel.maxEvents));
  });

  test('clear empties everything', () {
    store.ingest('use_case_execution', {
      'executionId': 1,
      'useCase': 'A',
      'event': 'E',
    });
    store.ingest('state_emission', {'bloc': 'B'});
    store.clear();
    expect(store.events, isEmpty);
    expect(store.spans, isEmpty);
    expect(store.blocs, isEmpty);
  });
}
