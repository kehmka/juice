import 'package:juice/juice.dart';
import '../auth_bloc.dart';
import '../events/auth_events.dart';
import '../states/auth_state.dart';

class LoginUseCase extends BlocUseCase<AuthBloc, LoginEvent> {
  @override
  Future<void> execute(LoginEvent event) async {
    // Show loading state
    emitWaiting(newState: bloc.state.copyWith(isLoading: true));

    // Simulate API call
    await Future.delayed(const Duration(seconds: 1));

    // Simulate successful login
    final userId = 'user_${DateTime.now().millisecondsSinceEpoch}';

    // Update state and emit LoginSuccessEvent
    // The LoginSuccessEvent can be subscribed to by other blocs
    emitUpdate(
      newState: AuthState(
        userId: userId,
        email: event.email,
        isAuthenticated: true,
        isLoading: false,
      ),
    );

    // Emit the success event so other blocs can react
    emitEvent(event: LoginSuccessEvent(userId: userId, email: event.email));
  }
}
