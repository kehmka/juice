import 'package:juice/juice.dart';
import '../user_profile_bloc.dart';
import '../events/user_profile_events.dart';
import '../states/user_profile_state.dart';

class LoadProfileUseCase extends BlocUseCase<UserProfileBloc, LoadProfileEvent> {
  @override
  Future<void> execute(LoadProfileEvent event) async {
    // Show loading
    emitWaiting(
      newState: bloc.state.copyWith(isLoading: true, error: null),
    );

    // Simulate API call to load profile
    await Future.delayed(const Duration(milliseconds: 500));

    // Simulate profile data
    emitUpdate(
      newState: UserProfileState(
        userId: event.userId,
        displayName: 'User ${event.email.split('@').first}',
        avatarUrl: 'https://i.pravatar.cc/150?u=${event.userId}',
        isLoading: false,
      ),
    );
  }
}
