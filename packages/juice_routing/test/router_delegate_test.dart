import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_routing/juice_routing.dart';

/// A guard that refuses (or allows) every navigation it is asked about.
class _Refuse extends RouteGuard {
  const _Refuse({this.allow = false});
  final bool allow;

  @override
  Future<GuardResult> check(RouteContext context) async => allow
      ? const GuardResult.allow()
      : const GuardResult.block(reason: 'not today');
}

/// A guard that throws, as a guard waiting on a session that never became
/// known does when its wait times out.
class _Throw extends RouteGuard {
  const _Throw();

  @override
  Future<GuardResult> check(RouteContext context) async =>
      throw StateError('the session never became known');
}

/// `JuiceRouterDelegate` with a start that could not be opened: the page
/// says so, where it used to show the loading page for ever.
void main() {
  Future<RoutingBloc> start(WidgetTester tester, RoutingConfig config) async {
    final bloc = RoutingBloc.withConfig(config);
    addTearDown(bloc.close);
    await tester.pumpWidget(MaterialApp.router(
      routerDelegate: JuiceRouterDelegate(routingBloc: bloc),
      routeInformationParser: const JuiceRouteInformationParser(),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    return bloc;
  }

  RoutingConfig refusedAt(String path, RouteGuard guard,
          {Widget Function(BuildContext, RoutingError)? errorBuilder}) =>
      RoutingConfig(
        routes: [
          RouteConfig(
            path: '/',
            builder: (_) => const Text('home'),
            guards: [guard],
          ),
        ],
        initialPath: path,
        errorBuilder: errorBuilder,
      );

  testWidgets('a guard that blocks the start: the page names the error',
      (tester) async {
    final bloc = await start(tester, refusedAt('/', const _Refuse()));

    expect(bloc.state.isInitialized, isTrue);
    expect(bloc.state.stack, isEmpty);
    expect(bloc.state.error, isA<GuardBlockedError>());
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'not the loading page');
    expect(find.byKey(const ValueKey('routing-error-text')), findsOneWidget);
    expect(find.textContaining('not today'), findsOneWidget);
  });

  testWidgets('a guard that throws on the start: the page names the error',
      (tester) async {
    final bloc = await start(tester, refusedAt('/', const _Throw()));

    expect(bloc.state.error, isA<GuardExceptionError>());
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
        find.textContaining('the session never became known'), findsOneWidget);
  });

  testWidgets('the app\'s own errorBuilder is used, handed the error',
      (tester) async {
    RoutingError? handed;
    await start(
        tester,
        refusedAt('/', const _Refuse(), errorBuilder: (context, error) {
          handed = error;
          return const Text('our own page');
        }));

    expect(find.text('our own page'), findsOneWidget);
    expect(handed, isA<GuardBlockedError>());
  });

  testWidgets('a start that opens shows its page, not the error page',
      (tester) async {
    await start(tester, refusedAt('/', const _Refuse(allow: true)));

    expect(find.text('home'), findsOneWidget);
    expect(find.byKey(const ValueKey('routing-error-text')), findsNothing);
  });
}
