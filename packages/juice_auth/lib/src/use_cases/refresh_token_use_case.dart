import 'package:juice/juice.dart';

import '../auth_bloc.dart';
import '../auth_errors.dart';
import '../auth_events.dart';
import '../auth_state.dart';

/// Handles [RefreshTokenEvent] — a droppable, singleflight token refresh.
///
/// The bloc's event registration drops overlapping refresh events, so only one
/// provider call executes while observers follow the shared state lifecycle.
class RefreshTokenUseCase extends BlocUseCase<AuthBloc, RefreshTokenEvent> {
  @override
  Future<void> execute(RefreshTokenEvent event) async {
    final session = bloc.state.session;
    if (session?.refreshToken == null) {
      log('No refresh token available', level: Level.warning);
      emitFailure(
        newState: bloc.state.copyWith(
          lastError: NoRefreshTokenError(),
        ),
        groupsToRebuild: {AuthGroups.error},
        error: NoRefreshTokenError(),
      );
      return;
    }

    log('Token refresh started for ${session!.providerName}');

    try {
      emitUpdate(
        newState: bloc.state.copyWith(isRefreshing: true),
        groupsToRebuild: {AuthGroups.session},
      );

      final provider = bloc.config.providers[session.providerName]!;
      final result = await provider.refreshToken(session.refreshToken!);

      // Persist new tokens
      await bloc.persistTokens(session.providerName, result);

      // Reschedule refresh timer
      bloc.scheduleRefresh(result.expiresAt);

      final newSession = session.copyWith(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken ?? session.refreshToken,
        expiresAt: result.expiresAt,
        lastRefreshedAt: DateTime.now(),
      );

      emitUpdate(
        newState: bloc.state.copyWith(
          session: newSession,
          user: result.user,
          isRefreshing: false,
        ),
        groupsToRebuild: {AuthGroups.session},
      );

      log('Token refresh successful');
    } catch (e, st) {
      logError(e, st);

      // Refresh failed → session expired (not unauthenticated)
      emitFailure(
        newState: bloc.state.copyWith(
          status: AuthStatus.sessionExpired,
          isRefreshing: false,
          lastError: RefreshFailedError(e.toString()),
        ),
        groupsToRebuild: {
          AuthGroups.status,
          AuthGroups.session,
          AuthGroups.error
        },
        aviatorName: 'sessionExpired',
        error: RefreshFailedError(e.toString()),
        errorStackTrace: st,
      );
    }
  }
}
