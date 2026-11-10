import 'package:juice/juice.dart';
import '../auth/auth_bloc.dart';
import '../auth/states/auth_state.dart';
import 'events/user_profile_events.dart';
import 'states/user_profile_state.dart';
import 'use_cases/load_profile_use_case.dart';
import 'use_cases/clear_profile_use_case.dart';

/// UserProfileBloc demonstrates a [Reaction]: one bloc following another's
/// state.
///
/// It reacts to [AuthBloc]:
/// - when the auth state BECOMES authenticated, it loads the user's profile;
/// - when it becomes unauthenticated, it clears the profile.
///
/// The reactions are attached here, in the constructor body, and owned by
/// this bloc — they end when it closes. AuthBloc knows nothing about them:
/// it only emits its own state.
class UserProfileBloc extends JuiceBloc<UserProfileState> {
  UserProfileBloc()
      : super(
          const UserProfileState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadProfileEvent,
                  useCaseGenerator: () => LoadProfileUseCase(),
                  concurrency: EventConcurrency.concurrent,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ClearProfileEvent,
                  useCaseGenerator: () => ClearProfileUseCase(),
                  concurrency: EventConcurrency.concurrent,
                ),
          ],
          [],
        ) {
    // catchUp: this bloc is leased — built when the page opens. If the user
    // is ALREADY signed in then, the profile still loads.
    react(Reaction<AuthBloc, AuthState>.becomes(
      (auth) => auth.isAuthenticated,
      send: (auth) => LoadProfileEvent(
        userId: auth.userId!,
        email: auth.email!,
      ),
      atAttach: AtAttach.catchUp,
    ));

    // skip: a profile that was never loaded has nothing to clear.
    react(Reaction<AuthBloc, AuthState>.becomes(
      (auth) => !auth.isAuthenticated,
      send: (_) => ClearProfileEvent(),
      atAttach: AtAttach.skip,
    ));
  }
}
