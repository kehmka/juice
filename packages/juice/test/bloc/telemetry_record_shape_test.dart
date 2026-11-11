import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// The telemetry entry's SHAPE, pinned.
///
/// A send with every telemetry record built is priced on the size of
/// [JuiceTelemetry]. At 2.0.0 it had 29 stored fields; the reaction work
/// added three, and the benchmark's "telemetry records (3 per event)" row
/// went from 0.055 to 0.18 µs, a send with the records built from 0.63 to
/// 0.78 µs (`benchmarks/RESULTS.md`). A bisect showed that ONE more stored
/// field, the thirtieth, is enough. Timings are a release-time measurement; this count is
/// the per-step gate.
void main() {
  /// The stored fields the class named [name] declares in telemetry.dart.
  List<String> storedFields(String name) {
    final source = File('lib/src/bloc/src/telemetry.dart').readAsStringSync();
    final start = source.indexOf('final class $name {');
    expect(start, isNot(-1), reason: '$name is declared in telemetry.dart');
    final end = source.indexOf('\n}\n', start);
    final body = source.substring(start, end);
    return [
      for (final m in RegExp(r'^  final [^(;=]+ (\w+);', multiLine: true)
          .allMatches(body))
        m.group(1)!
    ];
  }

  test('the entry stores no more fields than it did at 2.0.0', () {
    final fields = storedFields('JuiceTelemetry');
    expect(fields, contains('kind'));
    expect(fields, contains('_wiring'));
    expect(fields.length, lessThanOrEqualTo(29),
        reason: 'a thirtieth stored field tripled the cost of building an '
            'entry. A new fact that only some kinds carry goes beside the '
            'entry, as the wiring facts do; then time '
            'benchmarks/lib/breakdown_main.dart before it ships. '
            'Stored now: $fields');
  });

  test('the eight wiring facts are not stored in the entry', () {
    final entry = storedFields('JuiceTelemetry');
    final wiring = storedFields('_TelemetryWiring');
    const facts = [
      'sourceBloc',
      'sourceEvent',
      'localEvent',
      'destBloc',
      'relay',
      'reaction',
      'causeExecutionId',
      'hopDepth',
    ];
    expect(wiring, facts);
    for (final fact in facts) {
      expect(entry, isNot(contains(fact)), reason: '$fact is held beside');
    }
  });

  group('the wiring facts read as they did when they were fields', () {
    test('an entry without any has none, and its map names none', () {
      final entry = JuiceTelemetry(
        JuiceTelemetryKind.stateEmitted,
        bloc: 'FooBloc',
        event: 'LoadFoo',
        status: EmissionKind.update,
        state: 1,
        groups: const {'foo'},
      );
      expect(entry.sourceBloc, isNull);
      expect(entry.sourceEvent, isNull);
      expect(entry.localEvent, isNull);
      expect(entry.destBloc, isNull);
      expect(entry.relay, isNull);
      expect(entry.reaction, isNull);
      expect(entry.causeExecutionId, isNull);
      expect(entry.hopDepth, isNull);
      for (final fact in const [
        'sourceBloc',
        'sourceEvent',
        'localEvent',
        'destBloc',
        'relay',
        'reaction',
        'causeExecutionId',
        'hopDepth',
      ]) {
        expect(entry.toMap().containsKey(fact), isFalse, reason: fact);
      }
      expect(entry.bloc, 'FooBloc');
      expect(entry.state, 1);
    });

    test('each fact, set alone, is read back and is in the map', () {
      final alone =
          <String, (JuiceTelemetry, Object? Function(JuiceTelemetry))>{
        'sourceBloc': (
          JuiceTelemetry(JuiceTelemetryKind.reactionFired, sourceBloc: 'A'),
          (e) => e.sourceBloc
        ),
        'sourceEvent': (
          JuiceTelemetry(JuiceTelemetryKind.reactionFired, sourceEvent: 'B'),
          (e) => e.sourceEvent
        ),
        'localEvent': (
          JuiceTelemetry(JuiceTelemetryKind.reactionFired, localEvent: 'C'),
          (e) => e.localEvent
        ),
        'destBloc': (
          JuiceTelemetry(JuiceTelemetryKind.reactionFired, destBloc: 'D'),
          (e) => e.destBloc
        ),
        'relay': (
          JuiceTelemetry(JuiceTelemetryKind.reactionFired, relay: 'E'),
          (e) => e.relay
        ),
        'reaction': (
          JuiceTelemetry(JuiceTelemetryKind.reactionFired, reaction: 'edge'),
          (e) => e.reaction
        ),
        'causeExecutionId': (
          JuiceTelemetry(JuiceTelemetryKind.useCaseStarted,
              causeExecutionId: 7),
          (e) => e.causeExecutionId
        ),
        'hopDepth': (
          JuiceTelemetry(JuiceTelemetryKind.useCaseStarted, hopDepth: 0),
          (e) => e.hopDepth
        ),
      };
      const values = {
        'sourceBloc': 'A',
        'sourceEvent': 'B',
        'localEvent': 'C',
        'destBloc': 'D',
        'relay': 'E',
        'reaction': 'edge',
        'causeExecutionId': 7,
        'hopDepth': 0,
      };
      for (final MapEntry(key: name, value: (entry, read)) in alone.entries) {
        expect(read(entry), values[name], reason: name);
        expect(entry.toMap()[name], values[name], reason: '$name in the map');
        for (final other in values.keys.where((k) => k != name)) {
          expect(entry.toMap().containsKey(other), isFalse,
              reason: '$other was not set beside $name');
        }
      }
    });

    test('a reaction\'s entry carries all of its facts together', () {
      final entry = JuiceTelemetry(
        JuiceTelemetryKind.reactionFired,
        sourceBloc: 'SettingsBloc',
        destBloc: 'NotesBloc',
        reaction: 'changes',
        causeExecutionId: 12,
        hopDepth: 2,
        event: 'ApplySettingsEvent',
      );
      expect(entry.toMap(), {
        'type': 'reaction',
        'action': 'fire',
        'event': 'ApplySettingsEvent',
        'sourceBloc': 'SettingsBloc',
        'destBloc': 'NotesBloc',
        'reaction': 'changes',
        'causeExecutionId': 12,
        'hopDepth': 2,
      });
    });
  });
}
