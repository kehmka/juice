import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import 'profile_state.dart';
import 'profile_events.dart';
import 'use_cases/load_profile_use_case.dart';

class ProfileBloc extends JuiceBloc<ProfileState> {
  final FetchBloc fetchBloc;

  ProfileBloc({required this.fetchBloc})
      : super(
          const ProfileState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadProfileEvent,
                  useCaseGenerator: () => LoadProfileUseCase(),
                ),
          ],
        );
}
