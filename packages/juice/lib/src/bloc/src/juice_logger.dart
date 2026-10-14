import "../../../juice.dart";

/// Where Juice's output goes.
///
/// Three entry points, two vocabularies:
///
/// - [record] receives the FRAMEWORK's telemetry — every use-case span,
///   every emission, every lifecycle and error entry — as a typed
///   [JuiceTelemetry]: one object per entry, fields read by name, nothing
///   stringified until a logger prints or ships it. The framework builds an
///   entry only when [JuiceLoggerConfig.logs] says its level is kept.
/// - [log] and [logError] receive FREE-FORM lines — yours (`BlocUseCase.log`,
///   `logState`, `logError`) and the family packages' — as a message with
///   an optional context map.
///
/// **The contract for implementers.** Telemetry values are live objects:
/// [JuiceTelemetry.state] is the emitted state, [JuiceTelemetry.groups] the
/// caller's set. Decide whether an entry is kept before touching them, and
/// never retain an entry — it pins the state it names. [logError] and error
/// entries are the fail-loud path: errors are rare and must stay visible,
/// so formatting eagerly there is acceptable.
///
/// The `record` of the smallest complete implementation forwards telemetry
/// to the free-form path:
///
/// ```dart
/// @override
/// void record(JuiceTelemetry e) => e.isError
///     ? logError(e.message, e.error!, e.stackTrace ?? StackTrace.empty,
///         context: e.toMap())
///     : log(e.message, level: e.level, context: e.toMap());
/// ```
abstract class JuiceLogger {
  /// Receives one framework telemetry entry, synchronously, on the thread
  /// that produced it. Entries below the telemetry floor are not built at
  /// all, with the exemptions [JuiceTelemetry.isError] names; an entry that
  /// arrives is one the floor kept. A throw from here is not caught by the
  /// framework. See [JuiceTelemetry] for the record and [JuiceTelemetryKind]
  /// for every kind.
  void record(JuiceTelemetry entry);

  /// Logs a message with the specified log level and optional context.
  ///
  /// [message] - The message to log
  /// [level] - The severity level of the log
  /// [context] - Additional structured data about the log entry. Values may
  /// be live objects (the emitting bloc's state, a group set); stringify
  /// only for lines you keep, and never hold on to the map. See the class
  /// doc.
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context});

  /// Logs an error with additional error details and stack trace.
  ///
  /// [message] - Description of the error
  /// [error] - The error object
  /// [stackTrace] - Stack trace of where the error occurred
  /// [context] - Additional structured data about the error
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context});
}

/// A [JuiceLogger] that DECLARES the lowest level it keeps.
///
/// The framework's per-event chatter — the use-case span pair and the
/// emission entry, all at [Level.info] — is built whether or not the logger
/// keeps it unless the logger says otherwise. A logger that implements this
/// interface tells the framework what it will keep, and the framework does
/// not build an entry below that: the cost follows the consumer.
///
/// Optional. A logger that only `implements JuiceLogger` is treated as
/// keeping everything. [JuiceLoggerConfig.minLevel] is a
/// global floor on top: the effective level is the HIGHER of the two, so the
/// global knob can silence more but can never force entries into a logger
/// that declared it drops them.
///
/// [minLevel] is read on every gated entry, so it may change at run time
/// (a DevTools panel attaching, a remote log level) and must be cheap.
///
/// Never gated, whatever is declared: [logError], every error kind, and the
/// kinds [JuiceTelemetry.isError] lists (`emissionAfterClose`,
/// `eventIgnored`, `leasedBlocGot`, `streamBindingRefused`, a failure
/// `stateEmitted`). Those are still delivered — a logger that must not see
/// them filters them itself.
///
/// **Wrapping another logger?** Only the CONFIGURED logger's declaration
/// counts. A wrapper that does not implement this interface receives
/// everything; one that delegates [minLevel] to its inner logger inherits
/// the inner logger's silence (the [DefaultJuiceLogger] keeps nothing
/// outside debug builds). Declare what YOUR logger consumes.
abstract interface class LevelAwareJuiceLogger implements JuiceLogger {
  /// The lowest level this logger keeps. [Level.all] keeps everything,
  /// [Level.off] nothing.
  Level get minLevel;
}

/// Default implementation of [JuiceLogger] using the Logger package.
///
/// Declares its level ([LevelAwareJuiceLogger]) as exactly what the `logger`
/// package's default filter already does: that filter decides inside an
/// `assert`, so it keeps lines at or above `Logger.level` when asserts are
/// enabled (debug builds, tests) and keeps NOTHING otherwise (profile and
/// release). So an app that never configures a logger pays for no chatter
/// in release, and loses no line it ever printed.
class DefaultJuiceLogger implements LevelAwareJuiceLogger {
  /// Internal logger instance
  final Logger _logger;

  /// Creates a DefaultJuiceLogger with optional custom Logger configuration.
  DefaultJuiceLogger({Logger? logger})
      : _lazy = logger == null,
        _logger = logger ??
            Logger(
              printer: PrettyPrinter(
                methodCount: 2,
                errorMethodCount: 8,
                lineLength: 80,
                colors: true,
                printEmojis: true,
                dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
              ),
            );

  /// Whether lines are passed to [_logger] as closures (built only if the
  /// filter lets the line through). True for the default PrettyPrinter,
  /// which evaluates function messages; a caller-supplied [Logger] may use a
  /// printer that doesn't (LogfmtPrinter), so it gets eager strings.
  final bool _lazy;

  /// Whether asserts are enabled — the same test `logger`'s
  /// `DevelopmentFilter` makes, so the declaration below cannot drift from
  /// what the filter does.
  static final bool _assertsEnabled = () {
    var enabled = false;
    assert(() {
      enabled = true;
      return true;
    }());
    return enabled;
  }();

  /// With the default [Logger]: `Logger.level` when asserts are enabled,
  /// [Level.off] otherwise — what its filter keeps. With a caller-supplied
  /// [Logger] the filter is unknown (the package exposes no way to read
  /// it), so everything is declared kept; wrap it in your
  /// own [LevelAwareJuiceLogger] to declare its real level.
  @override
  Level get minLevel =>
      !_lazy ? Level.all : (_assertsEnabled ? Logger.level : Level.off);

  /// Prints the entry as `message | Context: {…}`; an error entry carries
  /// its error and stack trace in the printer's error slot. Under the
  /// default printer the line is built only if the filter keeps it.
  @override
  void record(JuiceTelemetry entry) => _write(
        entry.level,
        () => '${entry.message} | Context: ${entry.toMap()}',
        error: entry.isError ? entry.error : null,
        stackTrace: entry.isError ? entry.stackTrace : null,
      );

  @override
  void log(String message,
          {Level level = Level.info, Map<String, dynamic>? context}) =>
      _write(
          level,
          context == null
              ? () => message
              : () => '$message | Context: $context');

  @override
  void logError(String message, Object error, StackTrace stackTrace,
          {Map<String, dynamic>? context}) =>
      _write(
          Level.error,
          context == null
              ? () => message
              : () => '$message | Context: $context',
          error: error,
          stackTrace: stackTrace);

  /// The one writer: lazily under the default printer, eagerly otherwise.
  void _write(Level level, String Function() line,
          {Object? error, StackTrace? stackTrace}) =>
      _logger.log(level, _lazy ? line : line(),
          error: error, stackTrace: stackTrace);
}

/// Global configuration for Juice logging.
class JuiceLoggerConfig {
  /// Current logger instance, defaults to [DefaultJuiceLogger]
  static JuiceLogger _logger = DefaultJuiceLogger();

  /// Gets the currently configured logger
  static JuiceLogger get logger => _logger;

  /// Configures Juice to use a custom logger implementation
  static void configureLogger(JuiceLogger logger) {
    _logger = logger;
  }

  /// The global FLOOR for the framework's own per-event chatter.
  ///
  /// Every use-case execution logs a span pair and every emission logs an
  /// entry, at [Level.info] (benchmarks/RESULTS.md prices them). The
  /// framework builds an entry only if BOTH agree to it:
  ///
  /// 1. this floor — default [Level.all], so it gates nothing unless set;
  /// 2. the configured logger's own declaration, if it implements
  ///    [LevelAwareJuiceLogger] (the [DefaultJuiceLogger] does: everything
  ///    in debug, nothing in profile/release — what its filter keeps).
  ///
  /// So an unconfigured app already pays for no chatter in release. Set
  /// this to silence a logger that declares nothing, or to raise the floor
  /// above what a logger asks for; it cannot lower it.
  ///
  /// Never gates [JuiceLogger.logError], an error kind, or the kinds
  /// [JuiceTelemetry.isError] lists: those stay loud.
  static Level minLevel = Level.all;

  /// Whether an entry at [level] would be built and delivered at all: at or
  /// above the global floor AND at or above what the configured logger
  /// declares it keeps.
  static bool logs(Level level) {
    if (level.value < minLevel.value) return false;
    final logger = _logger;
    return logger is! LevelAwareJuiceLogger ||
        level.value >= logger.minLevel.value;
  }
}
