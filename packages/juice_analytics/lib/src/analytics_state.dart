import 'package:juice/juice.dart';

/// Rebuild groups emitted by `AnalyticsBloc`.
abstract final class AnalyticsGroups {
  /// Consent / user / counts changed.
  static const status = 'analytics:status';

  /// The current screen changed.
  static const screen = 'analytics:screen';

  static const all = {status, screen};
}

/// Immutable analytics state. Holds no event payloads — just consent and
/// bookkeeping (the events themselves go to the sinks).
class AnalyticsState extends BlocState {
  /// Whether tracking is permitted. When false, events are **dropped** (not
  /// buffered) so nothing leaks later without consent.
  final bool enabled;

  /// Current user id, if identified.
  final String? userId;

  /// Most recent screen name.
  final String? screenName;

  /// Events forwarded to sinks this session.
  final int eventCount;

  /// Events dropped because consent was off.
  final int droppedCount;

  const AnalyticsState({
    this.enabled = true,
    this.userId,
    this.screenName,
    this.eventCount = 0,
    this.droppedCount = 0,
  });

  static const initial = AnalyticsState();

  AnalyticsState copyWith({
    bool? enabled,
    Object? userId = _unset,
    Object? screenName = _unset,
    int? eventCount,
    int? droppedCount,
  }) {
    return AnalyticsState(
      enabled: enabled ?? this.enabled,
      userId: identical(userId, _unset) ? this.userId : userId as String?,
      screenName:
          identical(screenName, _unset) ? this.screenName : screenName as String?,
      eventCount: eventCount ?? this.eventCount,
      droppedCount: droppedCount ?? this.droppedCount,
    );
  }

  @override
  String toString() =>
      'AnalyticsState(enabled: $enabled, user: $userId, events: $eventCount, dropped: $droppedCount)';
}

const Object _unset = Object();
