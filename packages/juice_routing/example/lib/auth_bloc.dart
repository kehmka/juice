import 'package:juice/juice.dart';

// Auth state
class AuthState extends BlocState {
  final bool isLoggedIn;
  final String? username;
  final bool isAdmin;

  const AuthState({
    this.isLoggedIn = false,
    this.username,
    this.isAdmin = false,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    String? username,
    bool? isAdmin,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      username: username ?? this.username,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }
}

// Auth events
class LoginEvent extends EventBase {
  final String username;
  final bool asAdmin;
  LoginEvent(this.username, {this.asAdmin = false});
}

class LogoutEvent extends EventBase {}

// Auth use cases
class LoginUseCase extends BlocUseCase<AuthBloc, LoginEvent> {
  @override
  Future<void> execute(LoginEvent event) async {
    // Simulate login delay
    emitWaiting();
    await Future.delayed(const Duration(milliseconds: 500));

    emitUpdate(
      newState: bloc.state.copyWith(
        isLoggedIn: true,
        username: event.username,
        isAdmin: event.asAdmin,
      ),
    );
  }
}

class LogoutUseCase extends BlocUseCase<AuthBloc, LogoutEvent> {
  @override
  Future<void> execute(LogoutEvent event) async {
    emitUpdate(
      newState: const AuthState(isLoggedIn: false),
    );
  }
}

// Auth bloc
class AuthBloc extends JuiceBloc<AuthState> {
  AuthBloc()
      : super(
          const AuthState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoginEvent,
                  useCaseGenerator: () => LoginUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LogoutEvent,
                  useCaseGenerator: () => LogoutUseCase(),
                ),
          ],
        );

  void login(String username, {bool asAdmin = false}) =>
      send(LoginEvent(username, asAdmin: asAdmin));
  void logout() => send(LogoutEvent());
}
