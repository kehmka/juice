import 'package:juice/juice.dart';

import '../auth_bloc.dart';
import '../auth_events.dart';
import '../auth_state.dart';

/// Handles [LogoutEvent] — atomic cleanup of session, tokens, storage.
class LogoutUseCase extends BlocUseCase<AuthBloc, LogoutEvent> {
  @override
  Future<void> execute(LogoutEvent event) async {
    log('Logout requested (force: ${event.force})');

    final session = bloc.state.session;

    // 1. Cancel refresh timer
    bloc.cancelRefreshTimer();

    // 2. Revoke with provider (best-effort)
    if (!event.force && session != null) {
      final provider = bloc.config.providers[session.providerName];
      try {
        await provider?.revokeSession(session);
        log('Session revoked with ${session.providerName}');
      } catch (e, st) {
        logError(e, st);
        // Best-effort — don't block logout on revocation failure
      }
    }

    // 3. Clear secure storage
    await bloc.clearStoredTokens();

    // 4. Reset state
    emitUpdate(
      newState: const AuthState(status: AuthStatus.unauthenticated),
      groupsToRebuild: {
        AuthGroups.status,
        AuthGroups.user,
        AuthGroups.session,
      },
      aviatorName: 'logoutComplete',
    );

    log('Logout complete');
  }
}
