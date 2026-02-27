import 'package:juice/juice.dart';

import '../auth_bloc.dart';
import '../auth_events.dart';

/// Handles [TokenExpiryEvent] — triggered by refresh timer before token expiry.
///
/// Delegates to [RefreshTokenEvent] for the actual refresh logic.
class TokenExpiryUseCase extends BlocUseCase<AuthBloc, TokenExpiryEvent> {
  @override
  Future<void> execute(TokenExpiryEvent event) async {
    if (!bloc.state.isAuthenticated) return;

    log('Token expiry timer fired, triggering refresh');
    bloc.send(RefreshTokenEvent());
  }
}
