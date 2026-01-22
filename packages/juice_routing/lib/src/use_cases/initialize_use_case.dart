import 'package:juice/juice.dart';

import '../path_resolver.dart';
import '../routing_bloc.dart';
import '../routing_errors.dart';
import '../routing_events.dart';
import '../routing_state.dart';
import '../routing_types.dart';

/// Use case for initializing the routing system.
///
/// Creates the path resolver, resolves the initial path, and sets up
/// the initial stack state.
class InitializeUseCase
    extends BlocUseCase<RoutingBloc, InitializeRoutingEvent> {
  @override
  Future<void> execute(InitializeRoutingEvent event) async {
    final config = event.config;
    final initialPath = event.initialPath ?? config.initialPath;

    // Create and store path resolver in bloc
    final resolver = PathResolver(config);
    bloc.setConfig(config, resolver);

    // Resolve initial path
    final resolved = resolver.resolve(initialPath);
    if (resolved == null) {
      emitFailure(
        newState: bloc.state.copyWith(
          error: RouteNotFoundError(initialPath),
          isInitialized: true,
        ),
        groupsToRebuild: {RoutingGroups.error},
      );
      return;
    }

    // Create initial stack entry
    final entry = StackEntry(
      route: resolved.route,
      path: resolved.matchedPath,
      params: resolved.params,
      query: resolved.query,
      key: generateEntryKey(),
      pushedAt: DateTime.now(),
      scopeId: resolved.route.scopeName != null
          ? '${resolved.route.scopeName}_${generateEntryKey()}'
          : null,
    );

    // Create initial history entry
    final historyEntry = HistoryEntry(
      path: resolved.matchedPath,
      timestamp: DateTime.now(),
      type: NavigationType.push,
    );

    emitUpdate(
      newState: RoutingState(
        stack: [entry],
        history: [historyEntry],
        isInitialized: true,
      ),
      groupsToRebuild: RoutingGroups.all,
    );

    log('Initialized with path: ${resolved.matchedPath}');
  }
}
