// The two demo pages build and show what the reactions did.
import 'package:example/blocs/auth/auth.dart';
import 'package:example/blocs/auth/ui/auth_page.dart';
import 'package:example/blocs/relay_demo/relay_demo.dart';
import 'package:example/blocs/user_profile/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

void main() {
  tearDown(BlocScope.reset);

  testWidgets('the reactions demo page shows the destination following',
      (tester) async {
    BlocScope.register<SourceBloc>(() => SourceBloc());
    BlocScope.register<DestBloc>(() => DestBloc());
    // Built here, before any tap: DestBloc attaches its reactions.
    final dest = BlocScope.get<DestBloc>();

    await tester.pumpWidget(const MaterialApp(home: RelayDemoPage()));
    expect(find.text('Reactions Demo'), findsOneWidget);
    expect(find.text('How Reactions Work'), findsOneWidget);

    BlocScope.get<SourceBloc>().send(IncrementSourceEvent());
    await tester.pumpAndSettle();

    expect(dest.state.changesCount, 1);
    expect(find.text('Counter changed to 1'), findsOneWidget);
  });

  testWidgets('the auth demo page builds signed out', (tester) async {
    BlocScope.register<AuthBloc>(() => AuthBloc());
    BlocScope.register<UserProfileBloc>(() => UserProfileBloc(),
        lifecycle: BlocLifecycle.leased);

    await tester.pumpWidget(const MaterialApp(home: AuthPage()));

    expect(find.text('Auth & Reactions Demo'), findsOneWidget);
    expect(find.text('Reaction Demo'), findsOneWidget);
  });
}
