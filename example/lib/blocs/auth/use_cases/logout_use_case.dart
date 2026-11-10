import 'package:juice/juice.dart';
import '../auth_bloc.dart';
import '../events/auth_events.dart';
import '../states/auth_state.dart';

class LogoutUseCase extends BlocUseCase<AuthBloc, LogoutEvent> {
  @override
  Future<void> execute(LogoutEvent event) async {
    // Clear auth state. Other blocs react to it becoming unauthenticated.
    emitUpdate(
      newState: const AuthState(
        userId: null,
        email: null,
        isAuthenticated: false,
        isLoading: false,
      ),
    );
  }
}
