import 'package:juice/juice.dart';

import '../auth_bloc.dart';
import '../auth_errors.dart';
import '../auth_events.dart';
import '../auth_provider.dart';
import '../auth_session.dart';
import '../auth_state.dart';

/// Handles [LoginEvent] — authenticates via provider, persists tokens.
class LoginUseCase extends BlocUseCase<AuthBloc, LoginEvent> {
  @override
  Future<void> execute(LoginEvent event) async {
    log('Login requested for provider: ${event.providerName}');

    // 1. Rate limit check
    if (bloc.state.isRateLimited) {
      final remaining =
          bloc.state.loginCooldownUntil!.difference(DateTime.now());
      log('Login rate-limited, ${remaining.inSeconds}s remaining',
          level: Level.warning);
      emitFailure(
        newState: bloc.state.copyWith(
          lastError: RateLimitedError(remaining),
        ),
        groupsToRebuild: {AuthGroups.error},
        error: RateLimitedError(remaining),
      );
      return;
    }

    if (bloc.state.loginAttempts >= bloc.config.maxLoginAttempts) {
      final cooldownUntil = DateTime.now().add(bloc.config.loginCooldown);
      log('Max login attempts reached, cooldown until $cooldownUntil',
          level: Level.warning);
      emitFailure(
        newState: bloc.state.copyWith(
          loginCooldownUntil: cooldownUntil,
          lastError: RateLimitedError(bloc.config.loginCooldown),
        ),
        groupsToRebuild: {AuthGroups.error},
        error: RateLimitedError(bloc.config.loginCooldown),
      );
      return;
    }

    // 2. Resolve provider
    final provider = bloc.config.providers[event.providerName];
    if (provider == null) {
      log('Unknown provider: ${event.providerName}', level: Level.error);
      emitFailure(
        newState: bloc.state.copyWith(
          lastError: UnknownProviderError(event.providerName),
        ),
        groupsToRebuild: {AuthGroups.error},
        error: UnknownProviderError(event.providerName),
      );
      return;
    }

    // 3. Show loading
    emitWaiting();
    emitUpdate(
      newState: bloc.state.copyWith(
        pendingProvider: event.providerName,
        clearError: true,
      ),
      groupsToRebuild: {AuthGroups.status},
    );

    try {
      // 4. Authenticate
      final result = await provider.authenticate(event.credentials);
      log('Authentication successful for ${event.providerName}');

      // 5. Persist tokens to secure storage
      await bloc.persistTokens(event.providerName, result);

      // 6. Schedule refresh timer
      bloc.scheduleRefresh(result.expiresAt);

      // 7. Commit state
      emitUpdate(
        newState: AuthState(
          status: AuthStatus.authenticated,
          user: result.user,
          session: AuthSession(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: result.expiresAt,
            providerName: event.providerName,
            createdAt: DateTime.now(),
          ),
        ),
        groupsToRebuild: {
          AuthGroups.status,
          AuthGroups.user,
          AuthGroups.session,
        },
        aviatorName: 'loginSuccess',
        aviatorArgs: {'userId': result.user.id},
      );
    } on AuthProviderException catch (e, st) {
      final error = ProviderAuthError(
        e.message,
        providerName: event.providerName,
      );
      logError(e, st);
      emitFailure(
        newState: bloc.state.copyWith(
          loginAttempts: bloc.state.loginAttempts + 1,
          clearPendingProvider: true,
          lastError: error,
        ),
        groupsToRebuild: {AuthGroups.error},
        error: error,
        errorStackTrace: st,
      );
    }
  }
}
