import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// DefaultJuiceLogger (1.9.0) builds a context line only if the logger's
/// filter lets it through. Every emission logs a context holding the state;
/// built eagerly, its toString() ran on every emission, even in release
/// where the default filter drops the line. The benchmarks measured it.

class _Counting {
  int calls = 0;
  @override
  String toString() {
    calls++;
    return 'counted';
  }
}

void main() {
  late Level saved;
  setUp(() => saved = Logger.level);
  tearDown(() => Logger.level = saved);

  test('a filtered-out line never stringifies its context', () {
    Logger.level = Level.off; // what release effectively is for the filter
    final logger = DefaultJuiceLogger();
    final probe = _Counting();
    logger.log('emit', context: {'state': probe});
    logger.logError('boom', StateError('x'), StackTrace.current,
        context: {'state': probe});
    expect(probe.calls, 0);
  });

  test('a line that passes the filter is still fully formatted', () {
    Logger.level = Level.trace;
    final logger = DefaultJuiceLogger();
    final probe = _Counting();
    logger.log('emit', context: {'state': probe});
    expect(probe.calls, 1);
  });

  test(
      'a caller-supplied Logger keeps eager strings (its printer may not '
      'evaluate function messages)', () {
    Logger.level = Level.off;
    final logger = DefaultJuiceLogger(logger: Logger(printer: LogfmtPrinter()));
    final probe = _Counting();
    logger.log('emit', context: {'state': probe});
    expect(probe.calls, 1);
  });
}
