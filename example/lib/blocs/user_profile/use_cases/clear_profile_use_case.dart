import 'package:juice/juice.dart';
import '../user_profile_bloc.dart';
import '../events/user_profile_events.dart';
import '../states/user_profile_state.dart';

class ClearProfileUseCase extends BlocUseCase<UserProfileBloc, ClearProfileEvent> {
  @override
  Future<void> execute(ClearProfileEvent event) async {
    // Clear all profile data
    emitUpdate(
      newState: const UserProfileState(),
    );
  }
}
