import 'package:juice/juice.dart';

import '../auth_bloc.dart';
import '../auth_events.dart';
import '../auth_session.dart';
import '../auth_state.dart';

/// Handles [InitializeAuthEvent] — sets config and restores session from
/// secure storage.
///
/// Reads stored refresh token, refreshes with provider, transitions
/// to authenticated if successful, or unauthenticated if not.
class RestoreSessionUseCase
    extends BlocUseCase<AuthBloc, InitializeAuthEvent> {
  @override
  Future<void> execute(InitializeAuthEvent event) async {
    // Store config on the bloc
    bloc.setConfig(event.config);
    log('Auth initialized (restore: ${event.config.restoreSessionOnInit})');

    if (!event.config.restoreSessionOnInit) {
      emitUpdate(
        newState: const AuthState(status: AuthStatus.unauthenticated),
        groupsToRebuild: {AuthGroups.status},
      );
      return;
    }

    try {
      // 1. Read stored session metadata
      final storedSession = await bloc.readStoredSession();
      if (storedSession == null) {
        log('No stored session found');
        emitUpdate(
          newState: const AuthState(status: AuthStatus.unauthenticated),
          groupsToRebuild: {AuthGroups.status},
        );
        return;
      }

      final providerName = storedSession['providerName'] as String?;
      if (providerName == null) {
        log('Stored session has no provider name, clearing',
            level: Level.warning);
        await bloc.clearStoredTokens();
        emitUpdate(
          newState: const AuthState(status: AuthStatus.unauthenticated),
          groupsToRebuild: {AuthGroups.status},
        );
        return;
      }

      // 2. Read stored refresh token
      final refreshToken = await bloc.readStoredRefreshToken();
      if (refreshToken == null) {
        log('No stored refresh token for $providerName, clearing',
            level: Level.warning);
        await bloc.clearStoredTokens();
        emitUpdate(
          newState: const AuthState(status: AuthStatus.unauthenticated),
          groupsToRebuild: {AuthGroups.status},
        );
        return;
      }

      // 3. Resolve provider
      final provider = event.config.providers[providerName];
      if (provider == null || !provider.supportsRefresh) {
        log('Provider $providerName unavailable or no refresh support',
            level: Level.warning);
        await bloc.clearStoredTokens();
        emitUpdate(
          newState: const AuthState(status: AuthStatus.unauthenticated),
          groupsToRebuild: {AuthGroups.status},
        );
        return;
      }

      // 4. Refresh to get a fresh access token
      log('Restoring session via $providerName');
      final result = await provider.refreshToken(refreshToken);

      // 5. Persist new tokens
      await bloc.persistTokens(providerName, result);

      // 6. Schedule refresh timer
      bloc.scheduleRefresh(result.expiresAt);

      // 7. Commit authenticated state
      emitUpdate(
        newState: AuthState(
          status: AuthStatus.authenticated,
          user: result.user,
          session: AuthSession(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken ?? refreshToken,
            expiresAt: result.expiresAt,
            providerName: providerName,
            createdAt: DateTime.now(),
            lastRefreshedAt: DateTime.now(),
          ),
        ),
        groupsToRebuild: {
          AuthGroups.status,
          AuthGroups.user,
          AuthGroups.session,
        },
      );

      log('Session restored for user ${result.user.id}');
    } catch (e, st) {
      logError(e, st);
      // Restore failed — go to unauthenticated, clear stale tokens
      await bloc.clearStoredTokens();
      emitUpdate(
        newState: const AuthState(status: AuthStatus.unauthenticated),
        groupsToRebuild: {AuthGroups.status},
      );
    }
  }
}
