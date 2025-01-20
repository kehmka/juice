import 'package:juice/juice.dart';

enum ResetStreamType { onUpdate, onWaiting, onFailure }

/// Abstract base class for all events in JuiceBloc.
abstract class EventBase extends Object {
  EventBase({this.groupsToRebuild});
  Set<String>? groupsToRebuild;
  Future<void> close() async {}
}

class UpdateEvent<TState extends BlocState> extends EventBase {
  UpdateEvent(
      {this.newState,
      this.aviatorName,
      this.aviatorArgs,
      Set<String>? groupsToRebuild,
      this.resetStatusTo = ResetStreamType.onUpdate})
      : super(groupsToRebuild: groupsToRebuild ?? rebuildAlways);

  final TState? newState;
  final String? aviatorName;
  final Map<String, dynamic>? aviatorArgs;
  final ResetStreamType resetStatusTo;
}
