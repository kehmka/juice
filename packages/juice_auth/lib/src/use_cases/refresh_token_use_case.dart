import 'package:juice/juice.dart';

import '../auth_bloc.dart';
import '../auth_errors.dart';
import '../auth_events.dart';
import '../auth_state.dart';

/// Handles [RefreshTokenEvent] — a singleflight token refresh.
///
/// The bloc registers the event `singleflight`: a refresh requested while
/// this one runs joins it, so only one provider call executes and every
/// caller is answered with its session or its error.
class RefreshTokenUseCase extends BlocUseCase<AuthBloc, RefreshTokenEvent> {
  @override
  Future<void> execute(RefreshTokenEvent event) async {
    final session = bloc.state.session;
    if (session?.refreshToken == null) {
      log('No refresh token available', level: Level.warning);
      final error = NoRefreshTokenError();
      emitFailure(
        newState: bloc.state.copyWith(
          lastError: error,
        ),
        groupsToRebuild: {AuthGroups.error},
        error: error,
      );
      event.fail(error, StackTrace.current);
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

      event.succeed(newSession);
      log('Token refresh successful');
    } catch (e, st) {
      logError(e, st);
      final error = RefreshFailedError(e.toString());

      // Refresh failed → session expired (not unauthenticated)
      emitFailure(
        newState: bloc.state.copyWith(
          status: AuthStatus.sessionExpired,
          isRefreshing: false,
          lastError: error,
        ),
        groupsToRebuild: {
          AuthGroups.status,
          AuthGroups.session,
          AuthGroups.error
        },
        aviatorName: 'sessionExpired',
        error: error,
        errorStackTrace: st,
      );
      // `isRefreshing: true` was this event's first status, so an awaiting
      // caller is past it and waiting on the result.
      event.fail(error, st);
    }
  }
}
