import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_observability/juice_observability.dart';

/// A silent inner logger that records calls — proves the decorator always
/// forwards, and keeps test output clean.
class _RecordingLogger implements JuiceLogger {
  final logs = <String>[];
  final errors = <String>[];

  @override
  void log(String message,
          {Level level = Level.info, Map<String, dynamic>? context}) =>
      logs.add(message);

  @override
  void logError(String message, Object error, StackTrace stackTrace,
          {Map<String, dynamic>? context}) =>
      errors.add(message);
}

void main() {
  late _RecordingLogger inner;
  late List<(String, Map<String, Object?>)> posted;
  late DevtoolsJuiceLogger logger;

  setUp(() {
    inner = _RecordingLogger();
    posted = [];
    logger = DevtoolsJuiceLogger(
      inner: inner,
      post: (kind, data) => posted.add((kind, data)),
    );
  });

  test('a typed entry posts juice:<type> with type stripped from payload', () {
    logger.log('Emitting update', context: {
      'type': 'state_emission',
      'bloc': 'FooBloc',
      'groups': {'foo:status'},
    });
    expect(posted, hasLength(1));
    final (kind, data) = posted.single;
    expect(kind, 'juice:state_emission');
    expect(data['message'], 'Emitting update');
    expect(data['level'], 'info');
    expect(data['bloc'], 'FooBloc');
    expect(data.containsKey('type'), isFalse,
        reason: 'the discriminator became the event kind');
    expect(inner.logs, ['Emitting update'], reason: 'inner always forwards');
  });

  test('untyped chatter stays console-only', () {
    logger.log('plain message');
    logger.log('context but no type', context: {'detail': 1});
    expect(posted, isEmpty);
    expect(inner.logs, hasLength(2));
  });

  test('non-primitive context values cross as capped toString', () {
    final long = 'x' * 1000;
    logger.log('m', context: {
      'type': 'bloc_lifecycle',
      'state': _Verbose(long),
      'count': 3,
      'flag': true,
      'nothing': null,
    });
    final (_, data) = posted.single;
    final state = data['state'] as String;
    expect(state.length, DevtoolsJuiceLogger.maxFieldLength + 1); // + ellipsis
    expect(state.endsWith('…'), isTrue);
    expect(data['count'], 3, reason: 'primitives pass through untouched');
    expect(data['flag'], true);
    expect(data['nothing'], isNull);
  });

  test('errors always post — juice:error when untyped, its type when typed',
      () {
    logger.logError('boom', StateError('bad'), StackTrace.current);
    logger.logError('use case failed', StateError('worse'), StackTrace.current,
        context: {'type': 'use_case_error', 'useCase': 'LoadFoo'});
    expect(posted[0].$1, 'juice:error');
    expect(posted[0].$2['error'], contains('bad'));
    expect(posted[0].$2['stackTrace'], isNotEmpty);
    expect(posted[1].$1, 'juice:use_case_error');
    expect(posted[1].$2['useCase'], 'LoadFoo');
    expect(inner.errors, hasLength(2));
  });
}

class _Verbose {
  _Verbose(this.s);
  final String s;
  @override
  String toString() => s;
}
