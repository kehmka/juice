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

/// Default implementation of [JuiceLogger] using the Logger package.
class DefaultJuiceLogger implements JuiceLogger {
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
}
