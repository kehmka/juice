import 'package:juice/juice.dart';
import '../auth_bloc.dart';
import '../events/auth_events.dart';
import '../states/auth_state.dart';

class LogoutUseCase extends BlocUseCase<AuthBloc, LogoutEvent> {
  @override
  Future<void> execute(LogoutEvent event) async {
    // Clear auth state
    emitUpdate(
      newState: const AuthState(
        userId: null,
        email: null,
        isAuthenticated: false,
        isLoading: false,
      ),
    );

    // Emit the logout event so other blocs can react
    emitEvent(event: LogoutSuccessEvent());
  }
}
