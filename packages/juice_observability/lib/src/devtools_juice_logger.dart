import 'dart:developer' as developer;

import 'package:juice/juice.dart';

/// A [JuiceLogger] decorator that mirrors Juice's structured log entries to
/// the Dart VM's extension-event stream (`dart:developer` `postEvent`), where
/// DevTools and any VM-service listener can consume them live.
///
/// The framework already attaches a structured `context` map — with a `type`
/// discriminator — at every load-bearing point: `use_case_execution`,
/// `state_emission`, `state_emission_skipped`, `bloc_lifecycle`,
/// `event_subscription`, `unhandled_event`, `use_case_error`, `bloc_error`,
/// `error_handler_error`, `leak_detection`. This logger is a mirror on that
/// existing seam, not new instrumentation: every typed entry is posted as an
/// extension event of kind `juice:<type>`; untyped chatter stays
/// console-only. Errors without a typed context post as `juice:error` —
/// an error is always worth surfacing.
///
/// PHASE 1 — instant events only, deliberately. The core logs a use case's
/// START but not its completion, so duration spans cannot be honest yet;
/// when core gains a `use_case_completed` entry, Timeline spans slot in here
/// without breaking the event schema. (Tracked on the ROADMAP under the
/// BlocSignal tee-up.)
///
/// Wire it once at startup, wrapping whatever logger you already use:
///
/// ```dart
/// JuiceLoggerConfig.configureLogger(DevtoolsJuiceLogger());
/// // or, keeping a custom console logger:
/// JuiceLoggerConfig.configureLogger(DevtoolsJuiceLogger(inner: myLogger));
/// ```
class DevtoolsJuiceLogger implements JuiceLogger {
  /// [inner] receives every call unchanged (console logging keeps working);
  /// defaults to [DefaultJuiceLogger]. [post] is the VM seam — injectable so
  /// tests can capture instead of broadcasting; defaults to
  /// `dart:developer`'s [developer.postEvent].
  DevtoolsJuiceLogger({
    JuiceLogger? inner,
    void Function(String eventKind, Map<String, Object?> data)? post,
  })  : _inner = inner ?? DefaultJuiceLogger(),
        _post = post ?? developer.postEvent;

  final JuiceLogger _inner;
  final void Function(String eventKind, Map<String, Object?> data) _post;

  /// Extension-event payloads travel over the VM-service wire on every
  /// message; an unbounded `state.toString()` would make each emission a
  /// document. Values are capped, not dropped — the head of a state dump is
  /// the useful part.
  static const int maxFieldLength = 512;

  @override
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    _inner.log(message, level: level, context: context);
    final type = context?['type'];
    if (type is! String) return; // untyped chatter stays console-only
    _post('juice:$type', _payload(message, level, context!));
  }

  @override
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) {
    _inner.logError(message, error, stackTrace, context: context);
    final type = context?['type'];
    final kind = type is String ? 'juice:$type' : 'juice:error';
    _post(kind, {
      ..._payload(message, Level.error, context ?? const {}),
      'error': _clip(error.toString()),
      'stackTrace': _clip(stackTrace.toString()),
    });
  }

  Map<String, Object?> _payload(
      String message, Level level, Map<String, dynamic> context) {
    return {
      'message': _clip(message),
      'level': level.name,
      for (final e in context.entries)
        if (e.key != 'type') e.key: _sanitize(e.value),
    };
  }

  /// The wire wants JSON; the context holds live objects (states, blocs,
  /// events, group sets). Primitives pass through; everything else crosses
  /// as its [toString], capped.
  Object? _sanitize(Object? v) =>
      v == null || v is num || v is bool ? v : _clip(v.toString());

  String _clip(String s) =>
      s.length <= maxFieldLength ? s : '${s.substring(0, maxFieldLength)}…';
}
