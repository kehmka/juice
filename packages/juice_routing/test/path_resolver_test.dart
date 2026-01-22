import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_routing/juice_routing.dart';

void main() {
  group('PathResolver', () {
    group('literal path matching', () {
      test('matches exact path', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(path: '/about', builder: (_) => const SizedBox()),
            RouteConfig(path: '/contact', builder: (_) => const SizedBox()),
          ],
        );
        final resolver = PathResolver(config);

        final root = resolver.resolve('/');
        expect(root, isNotNull);
        expect(root!.matchedPath, '/');

        final about = resolver.resolve('/about');
        expect(about, isNotNull);
        expect(about!.matchedPath, '/about');

        final contact = resolver.resolve('/contact');
        expect(contact, isNotNull);
        expect(contact!.matchedPath, '/contact');
      });

      test('returns null for unmatched path without notFoundRoute', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
          ],
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('/nonexistent');
        expect(result, isNull);
      });

      test('returns notFoundRoute for unmatched path', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
          ],
          notFoundRoute: RouteConfig(
            path: '/404',
            builder: (_) => const SizedBox(),
          ),
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('/nonexistent');
        expect(result, isNotNull);
        expect(result!.route.path, '/404');
      });
    });

    group('parameter extraction', () {
      test('extracts single parameter', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/user/:id', builder: (_) => const SizedBox()),
          ],
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('/user/123');
        expect(result, isNotNull);
        expect(result!.params, {'id': '123'});
        expect(result.matchedPath, '/user/123');
      });

      test('extracts multiple parameters', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(
              path: '/org/:orgId/user/:userId',
              builder: (_) => const SizedBox(),
            ),
          ],
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('/org/acme/user/42');
        expect(result, isNotNull);
        expect(result!.params, {'orgId': 'acme', 'userId': '42'});
      });

      test('decodes URL-encoded parameters', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/search/:query', builder: (_) => const SizedBox()),
          ],
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('/search/hello%20world');
        expect(result, isNotNull);
        expect(result!.params['query'], 'hello world');
      });
    });

    group('query parameters', () {
      test('extracts query parameters', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/search', builder: (_) => const SizedBox()),
          ],
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('/search?q=flutter&page=1');
        expect(result, isNotNull);
        expect(result!.query, {'q': 'flutter', 'page': '1'});
        expect(result.matchedPath, '/search');
      });

      test('works with both path params and query params', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(
              path: '/user/:id/posts',
              builder: (_) => const SizedBox(),
            ),
          ],
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('/user/123/posts?sort=date&limit=10');
        expect(result, isNotNull);
        expect(result!.params, {'id': '123'});
        expect(result.query, {'sort': 'date', 'limit': '10'});
      });
    });

    group('wildcard matching', () {
      test('captures remaining path with wildcard', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/files/*', builder: (_) => const SizedBox()),
          ],
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('/files/documents/reports/q4.pdf');
        expect(result, isNotNull);
        expect(result!.params['*'], 'documents/reports/q4.pdf');
      });

      test('captures empty path with wildcard', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/files/*', builder: (_) => const SizedBox()),
          ],
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('/files/');
        expect(result, isNotNull);
        expect(result!.params['*'], '');
      });
    });

    group('nested routes', () {
      test('matches nested child routes', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(
              path: '/settings',
              builder: (_) => const SizedBox(),
              children: [
                RouteConfig(
                  path: 'profile',
                  builder: (_) => const SizedBox(),
                ),
                RouteConfig(
                  path: 'security',
                  builder: (_) => const SizedBox(),
                ),
              ],
            ),
          ],
        );
        final resolver = PathResolver(config);

        final settings = resolver.resolve('/settings');
        expect(settings, isNotNull);
        expect(settings!.matchedPath, '/settings');

        final profile = resolver.resolve('/settings/profile');
        expect(profile, isNotNull);
        expect(profile!.matchedPath, '/settings/profile');

        final security = resolver.resolve('/settings/security');
        expect(security, isNotNull);
        expect(security!.matchedPath, '/settings/security');
      });

      test('nested routes with parameters', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(
              path: '/user/:userId',
              builder: (_) => const SizedBox(),
              children: [
                RouteConfig(
                  path: 'post/:postId',
                  builder: (_) => const SizedBox(),
                ),
              ],
            ),
          ],
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('/user/123/post/456');
        expect(result, isNotNull);
        expect(result!.params, {'userId': '123', 'postId': '456'});
      });
    });

    group('path normalization', () {
      test('adds leading slash if missing', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/home', builder: (_) => const SizedBox()),
          ],
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('home');
        expect(result, isNotNull);
        expect(result!.matchedPath, '/home');
      });

      test('removes trailing slash', () {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/home', builder: (_) => const SizedBox()),
          ],
        );
        final resolver = PathResolver(config);

        final result = resolver.resolve('/home/');
        expect(result, isNotNull);
        expect(result!.matchedPath, '/home');
      });
    });
  });
}
