import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

// =============================================================================
// State
// =============================================================================

enum LogType { info, error, system }

class LogEntry {
  final String message;
  final LogType type;
  final DateTime timestamp;

  const LogEntry({
    required this.message,
    required this.type,
    required this.timestamp,
  });
}

class InterceptorsState extends BlocState {
  final List<LogEntry> logs;
  final bool loggingEnabled;
  final bool authEnabled;
  final bool timingEnabled;
  final String fakeToken;

  const InterceptorsState({
    this.logs = const [],
    this.loggingEnabled = true,
    this.authEnabled = false,
    this.timingEnabled = true,
    this.fakeToken = 'demo-jwt-token-12345',
  });

  InterceptorsState copyWith({
    List<LogEntry>? logs,
    bool? loggingEnabled,
    bool? authEnabled,
    bool? timingEnabled,
  }) {
    return InterceptorsState(
      logs: logs ?? this.logs,
      loggingEnabled: loggingEnabled ?? this.loggingEnabled,
      authEnabled: authEnabled ?? this.authEnabled,
      timingEnabled: timingEnabled ?? this.timingEnabled,
      fakeToken: fakeToken,
    );
  }
}

// =============================================================================
// Events
// =============================================================================

class ConfigureInterceptorsEvent extends EventBase {}

class ToggleLoggingEvent extends EventBase {
  final bool enabled;
  ToggleLoggingEvent(this.enabled);
}

class ToggleAuthEvent extends EventBase {
  final bool enabled;
  ToggleAuthEvent(this.enabled);
}

class ToggleTimingEvent extends EventBase {
  final bool enabled;
  ToggleTimingEvent(this.enabled);
}

class MakeRequestEvent extends EventBase {}

class MakeFailingRequestEvent extends EventBase {}

class ClearLogsEvent extends EventBase {}

class AddLogEvent extends EventBase {
  final String message;
  final LogType type;
  AddLogEvent(this.message, this.type);
}

// =============================================================================
// Use Cases
// =============================================================================

class ConfigureInterceptorsUseCase
    extends BlocUseCase<InterceptorsBloc, ConfigureInterceptorsEvent> {
  @override
  Future<void> execute(ConfigureInterceptorsEvent event) async {
    final interceptors = <FetchInterceptor>[];

    if (bloc.state.timingEnabled) {
      interceptors.add(TimingInterceptor());
    }

    if (bloc.state.loggingEnabled) {
      interceptors.add(LoggingInterceptor(
        logger: (msg) => bloc.addLog(msg, LogType.info),
        logBody: true,
        logHeaders: bloc.state.authEnabled,
      ));
    }

    if (bloc.state.authEnabled) {
      interceptors.add(AuthInterceptor(
        tokenProvider: () async => bloc.state.fakeToken,
        prefix: 'Bearer ',
      ));
    }

    await bloc.fetchBloc.send(ReconfigureInterceptorsEvent(
      interceptors: interceptors,
    ));

    bloc.addLog(
      'Interceptors configured: ${interceptors.map((i) => i.runtimeType.toString()).join(', ')}',
      LogType.system,
    );
  }
}

class ToggleLoggingUseCase extends BlocUseCase<InterceptorsBloc, ToggleLoggingEvent> {
  @override
  Future<void> execute(ToggleLoggingEvent event) async {
    emitUpdate(newState: bloc.state.copyWith(loggingEnabled: event.enabled));
  }
}

class ToggleAuthUseCase extends BlocUseCase<InterceptorsBloc, ToggleAuthEvent> {
  @override
  Future<void> execute(ToggleAuthEvent event) async {
    emitUpdate(newState: bloc.state.copyWith(authEnabled: event.enabled));
  }
}

class ToggleTimingUseCase extends BlocUseCase<InterceptorsBloc, ToggleTimingEvent> {
  @override
  Future<void> execute(ToggleTimingEvent event) async {
    emitUpdate(newState: bloc.state.copyWith(timingEnabled: event.enabled));
  }
}

class MakeRequestUseCase extends BlocUseCase<InterceptorsBloc, MakeRequestEvent> {
  @override
  Future<void> execute(MakeRequestEvent event) async {
    await bloc.fetchBloc.send(GetEvent(
      url: '/posts/1',
      cachePolicy: CachePolicy.networkOnly,
      decode: (raw) => raw,
    ));
  }
}

class MakeFailingRequestUseCase
    extends BlocUseCase<InterceptorsBloc, MakeFailingRequestEvent> {
  @override
  Future<void> execute(MakeFailingRequestEvent event) async {
    await bloc.fetchBloc.send(GetEvent(
      url: '/nonexistent/endpoint/404',
      cachePolicy: CachePolicy.networkOnly,
      decode: (raw) => raw,
    ));
  }
}

class ClearLogsUseCase extends BlocUseCase<InterceptorsBloc, ClearLogsEvent> {
  @override
  Future<void> execute(ClearLogsEvent event) async {
    emitUpdate(newState: bloc.state.copyWith(logs: []));
  }
}

class AddLogUseCase extends BlocUseCase<InterceptorsBloc, AddLogEvent> {
  @override
  Future<void> execute(AddLogEvent event) async {
    final entry = LogEntry(
      message: event.message,
      type: event.type,
      timestamp: DateTime.now(),
    );
    final newLogs = [entry, ...bloc.state.logs];
    if (newLogs.length > 100) newLogs.removeLast();
    emitUpdate(newState: bloc.state.copyWith(logs: newLogs));
  }
}

// =============================================================================
// Bloc
// =============================================================================

class InterceptorsBloc extends JuiceBloc<InterceptorsState> {
  final FetchBloc fetchBloc;

  InterceptorsBloc({required this.fetchBloc})
      : super(
          const InterceptorsState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: ConfigureInterceptorsEvent,
                  useCaseGenerator: () => ConfigureInterceptorsUseCase(),
                  initialEventBuilder: () => ConfigureInterceptorsEvent(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ToggleLoggingEvent,
                  useCaseGenerator: () => ToggleLoggingUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ToggleAuthEvent,
                  useCaseGenerator: () => ToggleAuthUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ToggleTimingEvent,
                  useCaseGenerator: () => ToggleTimingUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: MakeRequestEvent,
                  useCaseGenerator: () => MakeRequestUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: MakeFailingRequestEvent,
                  useCaseGenerator: () => MakeFailingRequestUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ClearLogsEvent,
                  useCaseGenerator: () => ClearLogsUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: AddLogEvent,
                  useCaseGenerator: () => AddLogUseCase(),
                ),
          ],
        );

  void addLog(String message, LogType type) {
    send(AddLogEvent(message, type));
  }
}
