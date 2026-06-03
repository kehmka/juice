import 'package:juice/juice.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_network/juice_network.dart';

/// Rebuild groups for [ProfileBloc].
abstract final class ProfileGroups {
  static const profile = 'profile:data';
}

// =============================================================================
// State
// =============================================================================

class ProfileState extends BlocState {
  /// The access token `AuthBlocAuthInterceptor` injects on the request.
  final String? injectedToken;

  /// The decoded `/profile` response body.
  final String? profileBody;

  final bool isLoading;
  final String? error;

  const ProfileState({
    this.injectedToken,
    this.profileBody,
    this.isLoading = false,
    this.error,
  });

  ProfileState copyWith({
    String? injectedToken,
    String? profileBody,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ProfileState(
      injectedToken: injectedToken ?? this.injectedToken,
      profileBody: profileBody ?? this.profileBody,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// =============================================================================
// Events
// =============================================================================

/// Load the authenticated `/profile` resource through [FetchBloc].
class LoadProfileEvent extends EventBase {}

// =============================================================================
// Use Cases
// =============================================================================

class LoadProfileUseCase extends BlocUseCase<ProfileBloc, LoadProfileEvent> {
  @override
  Future<void> execute(LoadProfileEvent event) async {
    // The token AuthBlocAuthInterceptor injects comes from the same source:
    // the current AuthBloc session.
    final token = bloc.authBloc.state.session?.accessToken;

    emitUpdate(
      newState: bloc.state.copyWith(
        isLoading: true,
        injectedToken: token,
        clearError: true,
      ),
      groupsToRebuild: {ProfileGroups.profile},
    );

    try {
      await bloc.fetchBloc.send(GetEvent(
        url: '/users/1',
        cachePolicy: CachePolicy.networkOnly,
        decode: (raw) {
          emitUpdate(
            newState: bloc.state.copyWith(
              profileBody: raw.toString(),
              isLoading: false,
            ),
            groupsToRebuild: {ProfileGroups.profile},
          );
          return raw;
        },
      ));
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(isLoading: false, error: e.toString()),
        groupsToRebuild: {ProfileGroups.profile},
      );
    }
  }
}

// =============================================================================
// Bloc
// =============================================================================

/// Feature bloc that loads the authenticated profile through [FetchBloc].
///
/// Holds the [AuthBloc] only to display which token gets injected; the actual
/// injection is handled by `AuthBlocAuthInterceptor` on the [FetchBloc].
class ProfileBloc extends JuiceBloc<ProfileState> {
  final FetchBloc fetchBloc;
  final AuthBloc authBloc;

  ProfileBloc({required this.fetchBloc, required this.authBloc})
      : super(
          const ProfileState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadProfileEvent,
                  useCaseGenerator: () => LoadProfileUseCase(),
                ),
          ],
        );

  /// Load the authenticated profile.
  void load() => send(LoadProfileEvent());
}
