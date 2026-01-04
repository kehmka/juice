// ignore_for_file: deprecated_member_use_from_same_package

import 'package:juice/juice.dart';

enum ResetStreamType { onUpdate, onWaiting, onFailure }

/// Abstract base class for all events in JuiceBloc.
abstract class EventBase extends Object {
  EventBase({this.groupsToRebuild});
  Set<String>? groupsToRebuild;
  Future<void> close() async {}
}

/// Built-in event for triggering UI updates, navigation, and status changes.
///
/// UpdateEvent is automatically handled by [UpdateUseCase] which is registered
/// with all blocs. Use this for:
/// - Triggering initial UI emissions via `bloc.start()`
/// - Navigation triggers via [aviatorName] and [aviatorArgs]
/// - Resetting stream status (e.g., from failure back to updating)
///
/// **Important**: Avoid using [newState] for state changes. State mutations
/// should go through dedicated use cases to maintain clean architecture.
/// The [newState] parameter is deprecated and will be removed in v2.0.0.
///
/// Example (correct usage):
/// ```dart
/// // Navigation trigger
/// bloc.send(UpdateEvent(aviatorName: 'home'));
///
/// // Reset status after error recovery
/// bloc.send(UpdateEvent(resetStatusTo: ResetStreamType.onUpdate));
/// ```
///
/// Example (incorrect - use a dedicated UseCase instead):
/// ```dart
/// // DON'T DO THIS - bypasses use case pattern
/// bloc.send(UpdateEvent(newState: state.copyWith(count: 5)));
///
/// // DO THIS - create a proper use case
/// bloc.send(SetCountEvent(count: 5));
/// ```
class UpdateEvent<TState extends BlocState> extends EventBase {
  UpdateEvent({
    @Deprecated('Use a dedicated UseCase for state changes. Will be removed in v2.0.0.')
    this.newState,
    this.aviatorName,
    this.aviatorArgs,
    Set<String>? groupsToRebuild,
    this.resetStatusTo = ResetStreamType.onUpdate,
  }) : super(groupsToRebuild: groupsToRebuild ?? rebuildAlways);

  /// The new state to emit.
  ///
  /// **Deprecated**: State changes should go through dedicated use cases.
  /// This parameter bypasses the use case pattern and will be removed in v2.0.0.
  @Deprecated('Use a dedicated UseCase for state changes. Will be removed in v2.0.0.')
  final TState? newState;

  /// Optional aviator name to trigger navigation.
  final String? aviatorName;

  /// Optional arguments to pass to the aviator.
  final Map<String, dynamic>? aviatorArgs;

  /// The stream status type to emit. Defaults to [ResetStreamType.onUpdate].
  final ResetStreamType resetStatusTo;
}
