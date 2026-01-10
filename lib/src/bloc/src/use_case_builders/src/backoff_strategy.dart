import 'dart:math';

/// Strategy for calculating delay between retry attempts.
///
/// Implement this interface to create custom backoff strategies.
/// Built-in implementations: [FixedBackoff], [ExponentialBackoff].
abstract class BackoffStrategy {
  /// Calculates the delay before the next retry attempt.
  ///
  /// [attempt] is zero-indexed (0 = first retry, 1 = second retry, etc.)
  Duration delay(int attempt);
}

/// Fixed delay between retry attempts.
///
/// Example:
/// ```dart
/// FixedBackoff(Duration(seconds: 2))
/// // Delays: 2s, 2s, 2s, ...
/// ```
class FixedBackoff implements BackoffStrategy {
  /// The fixed duration to wait between retries.
  final Duration duration;

  /// Creates a fixed backoff strategy.
  ///
  /// [duration] - The delay between each retry attempt.
  const FixedBackoff(this.duration);

  @override
  Duration delay(int attempt) => duration;
}

/// Exponential backoff with optional jitter.
///
/// Delays grow exponentially: initial * (multiplier ^ attempt)
///
/// Example without jitter:
/// ```dart
/// ExponentialBackoff(initial: Duration(seconds: 1))
/// // Delays: 1s, 2s, 4s, 8s, ...
/// ```
///
/// Example with jitter (randomizes 50-100% of calculated delay):
/// ```dart
/// ExponentialBackoff(initial: Duration(seconds: 1), jitter: true)
/// // Delays: ~0.5-1s, ~1-2s, ~2-4s, ...
/// ```
class ExponentialBackoff implements BackoffStrategy {
  /// Initial delay for the first retry.
  final Duration initial;

  /// Multiplier applied for each subsequent attempt (default: 2.0).
  final double multiplier;

  /// Maximum delay cap (optional).
  final Duration? maxDelay;

  /// Whether to add randomization to prevent thundering herd.
  final bool jitter;

  final Random _random = Random();

  /// Creates an exponential backoff strategy.
  ///
  /// [initial] - Base delay for first retry.
  /// [multiplier] - Growth factor (default 2.0 = double each time).
  /// [maxDelay] - Optional cap on maximum delay.
  /// [jitter] - Add randomization to spread out retries (default false).
  ExponentialBackoff({
    required this.initial,
    this.multiplier = 2.0,
    this.maxDelay,
    this.jitter = false,
  });

  @override
  Duration delay(int attempt) {
    // Calculate base delay: initial * multiplier^attempt
    var delayMs = initial.inMilliseconds * pow(multiplier, attempt);

    // Apply max cap if specified
    if (maxDelay != null) {
      delayMs = min(delayMs, maxDelay!.inMilliseconds.toDouble());
    }

    // Apply jitter: randomize between 50-100% of delay
    if (jitter) {
      delayMs = delayMs * (0.5 + _random.nextDouble() * 0.5);
    }

    return Duration(milliseconds: delayMs.toInt());
  }
}

/// Linear backoff that increases delay by a fixed amount each attempt.
///
/// Example:
/// ```dart
/// LinearBackoff(initial: Duration(seconds: 1), increment: Duration(seconds: 1))
/// // Delays: 1s, 2s, 3s, 4s, ...
/// ```
class LinearBackoff implements BackoffStrategy {
  /// Initial delay for the first retry.
  final Duration initial;

  /// Amount to add for each subsequent attempt.
  final Duration increment;

  /// Maximum delay cap (optional).
  final Duration? maxDelay;

  /// Creates a linear backoff strategy.
  const LinearBackoff({
    required this.initial,
    required this.increment,
    this.maxDelay,
  });

  @override
  Duration delay(int attempt) {
    var delayMs = initial.inMilliseconds + (increment.inMilliseconds * attempt);

    if (maxDelay != null) {
      delayMs = min(delayMs, maxDelay!.inMilliseconds);
    }

    return Duration(milliseconds: delayMs);
  }
}
