import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// Pins the classification flags and messages of the `JuiceException` family
/// (what retry logic and error UIs key on).

class _Custom extends JuiceException {
  const _Custom(super.message, {super.cause});
  @override
  bool get isRetryable => true;
}

void main() {
  test('base class: default flags, carries cause/stack, toString', () {
    final st = StackTrace.current;
    const cause = 'root';
    final e = _Custom('m', cause: cause);
    expect(e.isRetryable, isTrue);
    expect(e.isNetworkError, isFalse);
    expect(e.isValidationError, isFalse);
    expect(e.isTimeoutError, isFalse);
    expect(e.cause, cause);
    expect(e.toString(), '_Custom: m');
    expect(e, isA<Exception>());
    expect(StateException('s', stackTrace: st).stackTrace, same(st));
  });

  group('NetworkException', () {
    test('is retryable network error; 4xx/5xx classification', () {
      const none = NetworkException('down');
      expect(none.isRetryable, isTrue);
      expect(none.isNetworkError, isTrue);
      expect(none.isClientError, isFalse);
      expect(none.isServerError, isFalse);
      expect(none.toString(), 'NetworkException: down');

      const c = NetworkException('nf', statusCode: 404);
      expect(c.isClientError, isTrue);
      expect(c.isServerError, isFalse);
      expect(c.toString(), 'NetworkException: nf (status: 404)');

      const s = NetworkException('ise', statusCode: 503);
      expect(s.isClientError, isFalse);
      expect(s.isServerError, isTrue);

      const edge = NetworkException('ok', statusCode: 399);
      expect(edge.isClientError, isFalse);
      expect(edge.isServerError, isFalse);
      expect(
          const NetworkException('x', statusCode: 400).isClientError, isTrue);
      expect(
          const NetworkException('x', statusCode: 499).isClientError, isTrue);
      expect(
          const NetworkException('x', statusCode: 500).isServerError, isTrue);
    });
  });

  test('ValidationException: not retryable; field and errors carried', () {
    const plain = ValidationException('bad');
    expect(plain.isRetryable, isFalse);
    expect(plain.isValidationError, isTrue);
    expect(plain.isNetworkError, isFalse);
    expect(plain.toString(), 'ValidationException: bad');

    const f = ValidationException('req',
        field: 'email', errors: {'email': 'required'});
    expect(f.field, 'email');
    expect(f.errors, {'email': 'required'});
    expect(f.toString(), 'ValidationException: req (field: email)');
  });

  test('JuiceTimeoutException: retryable timeout; duration in toString', () {
    const t = JuiceTimeoutException('slow');
    expect(t.isRetryable, isTrue);
    expect(t.isTimeoutError, isTrue);
    expect(t.toString(), 'JuiceTimeoutException: slow');
    const d = JuiceTimeoutException('slow', duration: Duration(seconds: 30));
    expect(d.duration, const Duration(seconds: 30));
    expect(d.toString(), 'JuiceTimeoutException: slow (after 30s)');
  });

  test('Cancelled/State/Configuration exceptions are not retryable', () {
    const c = CancelledException('user');
    const s = StateException('closed');
    const k = ConfigurationException('missing');
    for (final JuiceException e in [c, s, k]) {
      expect(e.isRetryable, isFalse);
      expect(
          e.isNetworkError || e.isValidationError || e.isTimeoutError, isFalse);
    }
    expect(c.toString(), 'CancelledException: user');
    expect(s.toString(), 'StateException: closed');
    expect(k.toString(), 'ConfigurationException: missing');
  });
}
