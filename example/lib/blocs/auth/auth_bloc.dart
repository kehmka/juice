import 'package:juice/juice.dart';
import 'events/auth_events.dart';
import 'states/auth_state.dart';
import 'use_cases/login_use_case.dart';
import 'use_cases/logout_use_case.dart';

class AuthBloc extends JuiceBloc<AuthState> {
  AuthBloc()
      : super(
          const AuthState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoginEvent,
                  useCaseGenerator: () => LoginUseCase(),
                  concurrency: EventConcurrency.droppable,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LogoutEvent,
                  useCaseGenerator: () => LogoutUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
          ],
          [],
        );
}
