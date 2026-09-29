import "../../../juice.dart";

/// Interface for logging functionality in Juice framework.
///
/// Provides a standard logging interface that can be implemented to support
/// different logging backends or configurations.
///
/// **The contract for implementers (juice ≥ 1.9.1).** The framework calls
/// [log] on every use-case execution and every state emission, in every
/// build mode, and it passes context values as **live objects** — the
/// emission's `'state'` is the state itself and `'groups'` is the caller's
/// set — precisely so that a logger which drops a line pays nothing for it.
/// Two consequences:
///
/// - **Stringify lazily.** Decide whether the line will be kept (level,
///   environment, sampling) *before* touching `context`; `'$context'` or
///   `state.toString()` on every emission is the per-emission cost 1.9.1
///   removed from [DefaultJuiceLogger].
/// - **Do not retain `context`.** It holds the current state object; a
///   logger that buffers entries would pin every state it ever saw. Copy
///   what you keep as strings or primitives.
///
/// [logError] is the fail-loud path: errors are rare and must stay visible,
/// so formatting eagerly there is acceptable.
abstract class JuiceLogger {
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

/// A [JuiceLogger] that DECLARES the lowest level it keeps (juice ≥ 1.10.0).
///
/// The framework's per-event chatter — the use-case span pair and the
/// emission entry, all at [Level.info] — costs about a third of a dispatch
/// to BUILD, whether or not the logger keeps it. A logger that implements
/// this interface tells the framework what it will keep, and the framework
/// does not build an entry below that: the cost follows the consumer.
///
/// Optional. A logger that only `implements JuiceLogger` is treated as
/// keeping everything, exactly as before. [JuiceLoggerConfig.minLevel] is a
/// global floor on top: the effective level is the HIGHER of the two, so the
/// global knob can silence more but can never force entries into a logger
/// that declared it drops them.
///
/// [minLevel] is read on every gated entry, so it may change at run time
/// (a DevTools panel attaching, a remote log level) and must be cheap.
///
/// Never gated, whatever is declared: [logError], `emission_after_close`,
/// `event_ignored`, and a failure emission's entry. Those are still
/// delivered — a logger that must not see them filters them itself.
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

  /// Whether messages are passed to [_logger] as closures (built only if
  /// the filter lets the line through). True for the default PrettyPrinter,
  /// which evaluates function messages; a caller-supplied [Logger] may use a
  /// printer that doesn't (LogfmtPrinter), so it gets eager strings as before.
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
  /// it), so everything is declared kept, as before 1.10.0; wrap it in your
  /// own [LevelAwareJuiceLogger] to declare its real level.
  @override
  Level get minLevel =>
      !_lazy ? Level.all : (_assertsEnabled ? Logger.level : Level.off);

  @override
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    if (context == null) {
      _logger.log(level, message);
    } else if (_lazy) {
      // Every emission logs a context holding the state's toString(). Built
      // eagerly, that string was paid for on EVERY emission — in release
      // too, where logger's default filter then drops the line.
      _logger.log(level, () => '$message | Context: $context');
    } else {
      _logger.log(level, '$message | Context: $context');
    }
  }

  @override
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) {
    if (context != null) {
      _logger.e(
          _lazy
              ? () => '$message | Context: $context'
              : '$message | Context: $context',
          error: error,
          stackTrace: stackTrace);
    } else {
      _logger.e(message, error: error, stackTrace: stackTrace);
    }
  }
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

  /// The global FLOOR for the framework's own per-event chatter
  /// (juice ≥ 1.10.0).
  ///
  /// Every use-case execution logs a span pair and every emission logs an
  /// entry, at [Level.info]; building those context maps is about a third
  /// of a dispatch's cost (benchmarks/RESULTS.md §9). The framework builds
  /// an entry only if BOTH agree to it:
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
  /// Never gates [JuiceLogger.logError], `emission_after_close`,
  /// `event_ignored`, or a failure emission's entry: those stay loud.
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
