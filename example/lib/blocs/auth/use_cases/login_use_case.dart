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

    // Update state. Other blocs react to the STATE becoming authenticated —
    // there is no "login succeeded" event to announce it.
    emitUpdate(
      newState: AuthState(
        userId: userId,
        email: event.email,
        isAuthenticated: true,
        isLoading: false,
      ),
    );
  }
}
