import 'dart:developer' as developer;

import 'package:juice/juice.dart';

/// A [JuiceLogger] decorator that mirrors Juice's structured log entries to
/// the Dart VM's extension-event stream (`dart:developer` `postEvent`), where
/// DevTools and any VM-service listener can consume them live.
///
/// The framework hands every load-bearing entry to [record] as a typed
/// [JuiceTelemetry] (juice ≥ 2.0.0): the use-case span, every emission,
/// lifecycle, bindings, errors — see [JuiceTelemetryKind]. This logger is a
/// mirror on that seam, not new instrumentation: every entry is posted as an
/// extension event of kind `juice:<type>` with the entry's fields. Free-form
/// lines ([log] / [logError]) post only when their context carries a
/// `type`; untyped chatter stays console-only. Errors without a type post as
/// `juice:error` — an error is always worth surfacing.
///
/// SPANS: from juice 1.7.0 the core logs a `use_case_completed` end entry
/// (and stamps `use_case_error`) sharing the start's `executionId`, with
/// `elapsedMicros` — so a consumer can pair `juice:use_case_execution` with
/// its end event into an honest duration span, even when same-type events
/// overlap under `concurrent`.
///
/// COST FOLLOWS THE LISTENER (0.5.1, juice ≥ 1.10.0): this logger declares
/// its level ([LevelAwareJuiceLogger]) and builds payloads only while the
/// VM's Extension stream has a listener (`dart:developer`
/// `extensionStreamHasListener`). With a listener it declares [Level.all],
/// so the framework builds the full telemetry the panel consumes — in any
/// build mode a tool can attach to. With none it posts nothing, builds no
/// payload (no `state.toString()` per emission), and declares whatever
/// [inner] declares, so the framework's chatter is not built either. Read
/// on every entry: attaching DevTools mid-run turns the telemetry on live.
/// "A listener" includes the tooling daemon `flutter run` attaches, so
/// under `flutter run` telemetry is always on and the panel can replay the
/// daemon's history; an app launched on its own, and every release build,
/// pays nothing.
///
/// Wire it once at startup, wrapping whatever logger you already use:
///
/// ```dart
/// JuiceLoggerConfig.configureLogger(DevtoolsJuiceLogger());
/// // or, keeping a custom console logger:
/// JuiceLoggerConfig.configureLogger(DevtoolsJuiceLogger(inner: myLogger));
/// ```
class DevtoolsJuiceLogger implements LevelAwareJuiceLogger {
  /// [inner] receives every call unchanged (console logging keeps working);
  /// defaults to [DefaultJuiceLogger]. [post] is the VM seam — injectable so
  /// tests can capture instead of broadcasting; defaults to
  /// `dart:developer`'s [developer.postEvent]. [hasListener] is the other
  /// half of that seam — whether anyone would receive a post; defaults to
  /// `dart:developer`'s [developer.extensionStreamHasListener]. A test that
  /// injects [post] alone gets a listener that is always present, so its
  /// captures are not silently empty.
  DevtoolsJuiceLogger({
    JuiceLogger? inner,
    void Function(String eventKind, Map<String, Object?> data)? post,
    bool Function()? hasListener,
  })  : _inner = inner ?? DefaultJuiceLogger(),
        _post = post ?? developer.postEvent,
        _hasListener = hasListener ??
            (post != null
                ? _always
                : () => developer.extensionStreamHasListener);

  static bool _always() => true;

  final JuiceLogger _inner;
  final void Function(String eventKind, Map<String, Object?> data) _post;
  final bool Function() _hasListener;

  /// [Level.all] while a listener is attached (the panel consumes every
  /// entry); otherwise what [inner] declares — everything, if it declares
  /// nothing.
  @override
  Level get minLevel {
    if (_hasListener()) return Level.all;
    final inner = _inner;
    return inner is LevelAwareJuiceLogger ? inner.minLevel : Level.all;
  }

  /// Extension-event payloads travel over the VM-service wire on every
  /// message; an unbounded `state.toString()` would make each emission a
  /// document. Values are capped, not dropped — the head of a state dump is
  /// the useful part.
  static const int maxFieldLength = 512;

  /// The framework's telemetry: posted as `juice:<type>` with the entry's
  /// fields (its pre-2.0 map shape, `type` stripped), message and level,
  /// plus `error` / `stackTrace` for error entries. Built only with a
  /// listener.
  @override
  void record(JuiceTelemetry entry) {
    _inner.record(entry);
    if (!_hasListener()) return;
    final error = entry.error;
    _post('juice:${entry.kind.type}', {
      ..._payload(entry.message, entry.level, entry.toMap()),
      if (error != null) 'error': _clip(error.toString()),
      if (entry.stackTrace != null)
        'stackTrace': _clip(entry.stackTrace.toString()),
    });
  }

  @override
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    _inner.log(message, level: level, context: context);
    final type = context?['type'];
    if (type is! String) return; // untyped chatter stays console-only
    if (!_hasListener()) return; // nobody to receive it: build nothing
    _post('juice:$type', _payload(message, level, context!));
  }

  @override
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) {
    _inner.logError(message, error, stackTrace, context: context);
    if (!_hasListener()) return; // inner stays loud; the wire has no reader
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
