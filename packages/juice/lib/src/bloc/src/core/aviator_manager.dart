import 'dart:async';
import '../juice_logger.dart';
import '../aviators/aviator.dart';
import '../telemetry.dart';

/// Manages navigation aviators for a bloc.
///
/// Aviators provide a way to trigger navigation from within use cases
/// without coupling to specific navigation implementations. The manager
/// stores aviators by name and invokes them when requested.
///
/// Example:
/// ```dart
/// final manager = AviatorManager();
///
/// manager.register(DeepLinkAviator(
///   name: 'home',
///   navigateWhere: (args) => Navigator.pushNamed(context, '/home'),
/// ));
///
/// manager.navigate('home', {'userId': '123'});
/// ```
class AviatorManager {
  final _aviators = <String, AviatorBase>{};

  /// Registers an aviator.
  ///
  /// The aviator's [name] is used as the key for later lookups.
  /// If an aviator with the same name already exists, it is replaced.
  void register(AviatorBase aviator) {
    _aviators[aviator.name] = aviator;
  }

  /// Navigates using the named aviator.
  ///
  /// If [aviatorName] is null or no aviator exists with that name,
  /// this method does nothing (no-op).
  ///
  /// [args] are passed to the aviator's navigate function.
  ///
  /// An async navigation is not awaited (nothing awaits an emit's
  /// navigation).
  ///
  /// A failure in async navigation (an unknown deep link, a failing auth
  /// check) is logged as `aviator_error`. Nobody awaits this call — it runs
  /// from `emitUpdate(aviatorName:)` — so an unhandled error here used to
  /// escape as an uncaught zone error, outside every use case's handling.
  void navigate(String? aviatorName, Map<String, dynamic>? args) {
    if (aviatorName == null) return;
    final aviator = _aviators[aviatorName];
    if (aviator == null) return;
    try {
      final result = aviator.navigateWhere.call(args ?? {});
      if (result is Future<void>) {
        result.catchError((Object e, StackTrace st) => _logFailure(
              aviatorName,
              e,
              st,
            ));
      }
    } catch (e, st) {
      _logFailure(aviatorName, e, st);
    }
  }

  void _logFailure(String aviatorName, Object error, StackTrace stackTrace) {
    JuiceLoggerConfig.logger.record(JuiceTelemetry(
      JuiceTelemetryKind.aviatorFailed,
      aviator: aviatorName,
      error: error,
      stackTrace: stackTrace,
    ));
  }

  /// Closes all aviators and clears the registry.
  ///
  /// This should be called when the owning bloc is closed.
  Future<void> closeAll() async {
    await Future.wait(_aviators.values.map((a) => a.close()));
    _aviators.clear();
  }
}
