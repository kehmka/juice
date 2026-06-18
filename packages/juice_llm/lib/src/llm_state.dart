import 'package:juice/juice.dart';

/// Where the active model is in its acquire → load lifecycle.
enum LlmModelStatus {
  /// No model requested / not on disk.
  absent,

  /// Downloading weights ([LlmState.fetchProgress] is live).
  fetching,

  /// On disk and verified, not yet loaded into the runtime.
  fetched,

  /// Loading weights into the runtime.
  loading,

  /// Loaded and ready to generate.
  ready,

  /// A lifecycle step failed ([LlmState.error] holds the reason).
  error,
}

/// Lifecycle of a single generation request.
enum SessionStatus { queued, streaming, done, cancelled, failed }

/// One generation's accumulated state. A streaming text widget binds the
/// `llm:gen:<requestId>` group and reads [text]; nothing else rebuilds.
class GenerationSession {
  final String requestId;
  final SessionStatus status;

  /// Accumulated text so far.
  final String text;
  final int tokens;
  final String? error;

  const GenerationSession({
    required this.requestId,
    this.status = SessionStatus.queued,
    this.text = '',
    this.tokens = 0,
    this.error,
  });

  bool get isTerminal =>
      status == SessionStatus.done ||
      status == SessionStatus.cancelled ||
      status == SessionStatus.failed;

  GenerationSession copyWith({
    SessionStatus? status,
    String? text,
    int? tokens,
    Object? error = _unset,
  }) {
    return GenerationSession(
      requestId: requestId,
      status: status ?? this.status,
      text: text ?? this.text,
      tokens: tokens ?? this.tokens,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

/// Rebuild groups emitted by `LlmBloc`.
abstract final class LlmGroups {
  /// Model lifecycle status changed (gates "is the model awake" UI).
  static const model = 'llm:model';

  /// Download progress changed.
  static const fetch = 'llm:fetch';

  /// One generation session's tokens/status changed.
  /// `LlmGroups.gen(id)` → `llm:gen:<id>` (dynamic per request).
  static String gen(String requestId) => 'llm:gen:$requestId';

  /// Any session changed (for a list of sessions).
  static const sessions = 'llm:sessions';

  /// Catch-all.
  static const any = 'llm:any';

  /// Status-level groups. Per-session groups are dynamic — reach via [gen].
  static const all = {model, fetch, sessions, any};
}

/// Immutable LLM state.
class LlmState extends BlocState {
  final LlmModelStatus modelStatus;

  /// Id of the model that is loaded/loading/fetched, or null.
  final String? activeModelId;

  /// 0..1 while [modelStatus] is `fetching`, else null.
  final double? fetchProgress;

  /// Active + retained-completed sessions, keyed by requestId.
  final Map<String, GenerationSession> sessions;

  /// Last lifecycle (fetch/load) error, surfaced loudly. Session errors live
  /// on the session, not here.
  final String? error;

  const LlmState({
    this.modelStatus = LlmModelStatus.absent,
    this.activeModelId,
    this.fetchProgress,
    this.sessions = const {},
    this.error,
  });

  static const initial = LlmState();

  bool get isReady => modelStatus == LlmModelStatus.ready;

  LlmState copyWith({
    LlmModelStatus? modelStatus,
    Object? activeModelId = _unset,
    Object? fetchProgress = _unset,
    Map<String, GenerationSession>? sessions,
    Object? error = _unset,
  }) {
    return LlmState(
      modelStatus: modelStatus ?? this.modelStatus,
      activeModelId: identical(activeModelId, _unset)
          ? this.activeModelId
          : activeModelId as String?,
      fetchProgress: identical(fetchProgress, _unset)
          ? this.fetchProgress
          : (fetchProgress as num?)?.toDouble(),
      sessions: sessions ?? this.sessions,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  @override
  String toString() =>
      'LlmState($modelStatus, model: $activeModelId, ${sessions.length} sessions)';
}

const Object _unset = Object();
