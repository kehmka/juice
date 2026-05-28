import 'package:flutter_test/flutter_test.dart';
import 'package:juice_network/juice_network.dart';

/// Unit tests for [RequestKey] canonicalization and equality.
///
/// These tests pin the *actual* behavior of the implementation (code is the
/// source of truth). Where the behavior is a deliberate constraint rather than
/// an obvious property, the test name and comments call it out:
///
/// - The key is built from method + path + query + body/header/auth/variant.
///   The URL host/scheme/port are NOT part of the key — `FetchBloc` is scoped
///   to a single `baseUrl`, so identity is path-relative by design.
/// - Paths and query-parameter keys are lowercased during normalization.
void main() {
  group('RequestKey canonicalization', () {
    test('method is uppercased', () {
      final key = RequestKey.from(method: 'get', url: '/users');
      expect(key.method, 'GET');
      expect(key.canonical, startsWith('GET:'));
    });

    test('identical requests produce equal keys and hashCodes', () {
      final a = RequestKey.from(method: 'GET', url: '/users/1');
      final b = RequestKey.from(method: 'GET', url: '/users/1');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different methods produce different keys', () {
      final get = RequestKey.from(method: 'GET', url: '/users/1');
      final post = RequestKey.from(method: 'POST', url: '/users/1');
      expect(get, isNot(equals(post)));
    });

    group('path normalization', () {
      test('trailing slash is stripped (non-root)', () {
        final withSlash = RequestKey.from(method: 'GET', url: '/users/');
        final without = RequestKey.from(method: 'GET', url: '/users');
        expect(withSlash, equals(without));
      });

      test('double slashes are collapsed', () {
        final doubled = RequestKey.from(method: 'GET', url: '/users//1');
        final single = RequestKey.from(method: 'GET', url: '/users/1');
        expect(doubled, equals(single));
      });

      test('path is lowercased (deliberate constraint)', () {
        // Code is source of truth: paths are case-insensitive in the key.
        final upper = RequestKey.from(method: 'GET', url: '/Users/1');
        final lower = RequestKey.from(method: 'GET', url: '/users/1');
        expect(upper, equals(lower));
      });

      test('host/scheme are NOT part of the key (path-relative identity)', () {
        // FetchBloc is scoped to a single baseUrl, so two absolute URLs with
        // the same path collapse to the same key by design.
        final a = RequestKey.from(method: 'GET', url: 'https://a.com/users/1');
        final b = RequestKey.from(method: 'GET', url: 'https://b.com/users/1');
        expect(a, equals(b));
      });
    });

    group('query parameter canonicalization', () {
      test('order-independent: keys sorted', () {
        final a = RequestKey.from(method: 'GET', url: '/search?b=2&a=1');
        final b = RequestKey.from(method: 'GET', url: '/search?a=1&b=2');
        expect(a, equals(b));
      });

      test('repeated keys: values sorted and preserved', () {
        final a = RequestKey.from(method: 'GET', url: '/search?a=2&a=1');
        final b = RequestKey.from(method: 'GET', url: '/search?a=1&a=2');
        expect(a, equals(b));
      });

      test('different query values produce different keys', () {
        final a = RequestKey.from(method: 'GET', url: '/search?q=cats');
        final b = RequestKey.from(method: 'GET', url: '/search?q=dogs');
        expect(a, isNot(equals(b)));
      });

      test('no query produces null queryString', () {
        final key = RequestKey.from(method: 'GET', url: '/users');
        expect(key.queryString, isNull);
      });

      test('query key is lowercased (deliberate constraint)', () {
        final upper = RequestKey.from(method: 'GET', url: '/s?Q=cats');
        final lower = RequestKey.from(method: 'GET', url: '/s?q=cats');
        expect(upper, equals(lower));
      });
    });

    group('body hashing', () {
      test('JSON body hash is key-order independent', () {
        final a = RequestKey.from(
          method: 'POST',
          url: '/users',
          body: const {'a': 1, 'b': 2},
        );
        final b = RequestKey.from(
          method: 'POST',
          url: '/users',
          body: const {'b': 2, 'a': 1},
        );
        expect(a, equals(b));
        expect(a.bodyHash, isNotNull);
      });

      test('different bodies produce different keys', () {
        final a = RequestKey.from(
          method: 'POST',
          url: '/users',
          body: const {'name': 'Jane'},
        );
        final b = RequestKey.from(
          method: 'POST',
          url: '/users',
          body: const {'name': 'John'},
        );
        expect(a, isNot(equals(b)));
      });

      test('JSON string body equals equivalent map body', () {
        final fromString = RequestKey.from(
          method: 'POST',
          url: '/users',
          body: '{"b":2,"a":1}',
        );
        final fromMap = RequestKey.from(
          method: 'POST',
          url: '/users',
          body: const {'a': 1, 'b': 2},
        );
        expect(fromString, equals(fromMap));
      });

      test('nested JSON is recursively sorted', () {
        final a = RequestKey.from(
          method: 'POST',
          url: '/x',
          body: const {
            'b': 1,
            'a': {'d': 2, 'c': 3},
          },
        );
        final b = RequestKey.from(
          method: 'POST',
          url: '/x',
          body: const {
            'a': {'c': 3, 'd': 2},
            'b': 1,
          },
        );
        expect(a, equals(b));
      });

      test('body is ignored for GET (no bodyHash)', () {
        final key = RequestKey.from(
          method: 'GET',
          url: '/users',
          body: const {'ignored': true},
        );
        expect(key.bodyHash, isNull);
      });
    });

    group('identity headers', () {
      test('only identity headers affect the key', () {
        // User-Agent is NOT an identity header — should not change the key.
        final a = RequestKey.from(
          method: 'GET',
          url: '/x',
          headers: const {'User-Agent': 'foo'},
        );
        final b = RequestKey.from(method: 'GET', url: '/x');
        expect(a, equals(b));
      });

      test('Accept header changes the key', () {
        final json = RequestKey.from(
          method: 'GET',
          url: '/x',
          headers: const {'Accept': 'application/json'},
        );
        final xml = RequestKey.from(
          method: 'GET',
          url: '/x',
          headers: const {'Accept': 'application/xml'},
        );
        expect(json, isNot(equals(xml)));
        expect(json.headerVaryHash, isNotNull);
      });

      test('identity header name is case-insensitive', () {
        final a = RequestKey.from(
          method: 'GET',
          url: '/x',
          headers: const {'Accept': 'application/json'},
        );
        final b = RequestKey.from(
          method: 'GET',
          url: '/x',
          headers: const {'accept': 'application/json'},
        );
        expect(a, equals(b));
      });

      test('Authorization is NOT an identity header (use authScope)', () {
        final a = RequestKey.from(
          method: 'GET',
          url: '/x',
          headers: const {'Authorization': 'Bearer token-a'},
        );
        final b = RequestKey.from(
          method: 'GET',
          url: '/x',
          headers: const {'Authorization': 'Bearer token-b'},
        );
        expect(a, equals(b));
      });
    });

    group('authScope and variant', () {
      test('different authScope produces different keys', () {
        final a = RequestKey.from(
          method: 'GET',
          url: '/profile',
          authScope: 'bearer:user1',
        );
        final b = RequestKey.from(
          method: 'GET',
          url: '/profile',
          authScope: 'bearer:user2',
        );
        expect(a, isNot(equals(b)));
      });

      test('different variant produces different keys', () {
        final acme = RequestKey.from(
          method: 'GET',
          url: '/users',
          variant: 'tenant:acme',
        );
        final globex = RequestKey.from(
          method: 'GET',
          url: '/users',
          variant: 'tenant:globex',
        );
        expect(acme, isNot(equals(globex)));
      });
    });

    test('canonical exposes all present components', () {
      final key = RequestKey.from(
        method: 'POST',
        url: '/users?a=1',
        body: const {'x': 1},
        headers: const {'Accept': 'application/json'},
        authScope: 'bearer:u1',
        variant: 'tenant:acme',
      );
      expect(key.canonical, contains('POST'));
      expect(key.canonical, contains('/users'));
      expect(key.canonical, contains('a=1'));
      expect(key.bodyHash, isNotNull);
      expect(key.headerVaryHash, isNotNull);
      expect(key.authScope, 'bearer:u1');
      expect(key.variant, 'tenant:acme');
    });

    test('equality holds across full canonical component set', () {
      RequestKey make() => RequestKey.from(
            method: 'POST',
            url: '/users?b=2&a=1',
            body: const {'b': 2, 'a': 1},
            headers: const {'Accept': 'application/json'},
            authScope: 'bearer:u1',
            variant: 'tenant:acme',
          );
      expect(make(), equals(make()));
      expect(make().hashCode, equals(make().hashCode));
    });
  });
}
