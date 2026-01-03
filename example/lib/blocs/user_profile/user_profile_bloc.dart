import 'package:juice/juice.dart';
import '../auth/auth_bloc.dart';
import '../auth/events/auth_events.dart';
import 'events/user_profile_events.dart';
import 'states/user_profile_state.dart';
import 'use_cases/load_profile_use_case.dart';
import 'use_cases/clear_profile_use_case.dart';

/// UserProfileBloc demonstrates EventSubscription for bloc-to-bloc communication.
///
/// This bloc subscribes to AuthBloc's events:
/// - When LoginSuccessEvent is emitted, it loads the user's profile
/// - When LogoutSuccessEvent is emitted, it clears the profile
///
/// This is a loosely-coupled approach - UserProfileBloc only knows about
/// AuthBloc's event structure, not its state structure.
class UserProfileBloc extends JuiceBloc<UserProfileState> {
  UserProfileBloc()
      : super(
          const UserProfileState(),
          [
            // Subscribe to AuthBloc's LoginSuccessEvent
            // When user logs in, automatically load their profile
            () => EventSubscription<AuthBloc, LoginSuccessEvent, LoadProfileEvent>(
                  toEvent: (loginEvent) => LoadProfileEvent(
                    userId: loginEvent.userId,
                    email: loginEvent.email,
                  ),
                  useCaseGenerator: () => LoadProfileUseCase(),
                ),

            // Subscribe to AuthBloc's LogoutSuccessEvent
            // When user logs out, clear their profile
            () => EventSubscription<AuthBloc, LogoutSuccessEvent, ClearProfileEvent>(
                  toEvent: (_) => ClearProfileEvent(),
                  useCaseGenerator: () => ClearProfileUseCase(),
                ),
          ],
          [],
        );
}
