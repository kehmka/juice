// The two showcase demos of one bloc following another, tested the way the
// framework means it: a juiceFlowTest on a virtual clock. The demos'
// simulated API calls take one and two seconds; these tests take none.
import 'package:example/blocs/auth/auth.dart';
import 'package:example/blocs/relay_demo/relay_demo.dart';
import 'package:example/blocs/user_profile/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/testing.dart';

Matcher _profile({required bool loaded, bool loading = false}) =>
    isA<UserProfileState>()
        .having((s) => s.hasProfile, 'hasProfile', loaded)
        .having((s) => s.isLoading, 'isLoading', loading);

void main() {
  tearDown(BlocScope.reset);

  group('UserProfileBloc reacts to AuthBloc', () {
    juiceFlowTest('signing in loads the profile; signing out clears it',
        (flow) async {
      final auth = flow.register<AuthBloc>(() => AuthBloc());
      final profile = flow.register<UserProfileBloc>(() => UserProfileBloc());

      await flow.send(
          auth, LoginEvent(email: 'ada@example.com', password: 'x'));

      flow.expect(auth, [
        isWaitingStatus(),
        isUpdatingStatus(
            state: isA<AuthState>()
                .having((s) => s.isAuthenticated, 'isAuthenticated', true)),
      ]);
      flow.expect(profile, [
        isWaitingStatus(state: _profile(loaded: false, loading: true)),
        isUpdatingStatus(state: _profile(loaded: true)),
      ]);
      expect(profile.state.displayName, 'User ada');

      await flow.send(auth, LogoutEvent());

      flow.expect(auth, hasLength(1));
      flow.expect(profile, [isUpdatingStatus(state: _profile(loaded: false))]);
    }, virtualTime: true);

    juiceFlowTest(
        'a profile bloc built AFTER the sign-in still loads: the reaction '
        'catches up', (flow) async {
      final auth = flow.register<AuthBloc>(() => AuthBloc());
      await flow.send(
          auth, LoginEvent(email: 'late@example.com', password: 'x'));
      flow.expect(auth, hasLength(2));

      final profile = flow.register<UserProfileBloc>(() => UserProfileBloc());
      await flow.settle();

      flow.expect(profile, [
        isWaitingStatus(),
        isUpdatingStatus(state: _profile(loaded: true)),
      ]);
      expect(profile.state.displayName, 'User late');
    }, virtualTime: true);

    juiceFlowTest('a profile bloc built while signed out does nothing',
        (flow) async {
      flow.register<AuthBloc>(() => AuthBloc());
      final profile = flow.register<UserProfileBloc>(() => UserProfileBloc());
      await flow.settle();
      flow.expect(profile, isEmpty);
    }, virtualTime: true);
  });

  group('DestBloc reacts to SourceBloc', () {
    List<String> log(DestBloc dest) =>
        [for (final entry in dest.state.log) entry.toString()];

    juiceFlowTest('changes: each new counter value is logged once',
        (flow) async {
      final source = flow.register<SourceBloc>(() => SourceBloc());
      final dest = flow.register<DestBloc>(() => DestBloc());

      await flow.send(source, IncrementSourceEvent());
      await flow.send(source, IncrementSourceEvent());
      await flow.send(source, DecrementSourceEvent());

      expect(log(dest), [
        '[changes] Counter changed to 1',
        '[changes] Counter changed to 2',
        '[changes] Counter changed to 1',
      ]);
      expect(dest.state.changesCount, 3);
      expect(dest.state.becomesCount, 0);
      flow.expect(source, hasLength(3));
      flow.expect(dest, hasLength(3));
    }, virtualTime: true);

    juiceFlowTest('an emission that leaves the counter alone sends nothing',
        (flow) async {
      final source = flow.register<SourceBloc>(() => SourceBloc());
      final dest = flow.register<DestBloc>(() => DestBloc());

      await flow.send(source, ResetSourceEvent()); // already 0

      flow.expect(source, hasLength(1));
      flow.expect(dest, isEmpty);
    }, virtualTime: true);

    juiceFlowTest(
        'becomes: the async operation is logged as busy ONCE, then its '
        'counter change', (flow) async {
      final source = flow.register<SourceBloc>(() => SourceBloc());
      final dest = flow.register<DestBloc>(() => DestBloc());

      await flow.send(source, SimulateAsyncEvent()); // two seconds, virtual

      expect(log(dest), [
        '[becomes] Source became busy (async in progress)...',
        '[changes] Counter changed to 10',
      ]);
      expect(source.state.isProcessing, isFalse);
      flow.expect(source, [isWaitingStatus(), isUpdatingStatus()]);
      flow.expect(dest, hasLength(2));
    }, virtualTime: true);

    juiceFlowTest('becomes: an error in the source state is logged',
        (flow) async {
      final source = flow.register<SourceBloc>(() => SourceBloc());
      final dest = flow.register<DestBloc>(() => DestBloc());

      await flow.send(source, SimulateErrorEvent());

      expect(log(dest), ['[becomes] Source failed: Simulated error occurred!']);
      flow.expect(source, [isFailureStatus()]);
      flow.expect(dest, hasLength(1));

      // Still failed: a second error is not a new "becomes".
      await flow.send(source, SimulateErrorEvent());
      flow.expect(source, [isFailureStatus()]);
      flow.expect(dest, isEmpty);
    }, virtualTime: true);
  });
}
