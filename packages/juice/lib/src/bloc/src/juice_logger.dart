import "../../../juice.dart";

/// Interface for logging functionality in Juice framework.
///
/// Provides a standard logging interface that can be implemented to support
/// different logging backends or configurations.
abstract class JuiceLogger {
  /// Logs a message with the specified log level and optional context.
  ///
  /// [message] - The message to log
  /// [level] - The severity level of the log
  /// [context] - Additional structured data about the log entry
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
      : _logger = logger ??
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

  @override
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    if (context != null) {
      _logger.log(level, '$message | Context: $context');
    } else {
      _logger.log(level, message);
    }
  }

  @override
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) {
    if (context != null) {
      _logger.e('$message | Context: $context',
          error: error, stackTrace: stackTrace);
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
