import 'package:juice/juice.dart';

import '../realtime_bloc.dart';
import '../realtime_events.dart';
import '../realtime_state.dart';

/// Handles [MessageReceivedEvent] — fan the message out to the broadcast stream
/// (for every-message consumers) and record it as `lastMessage`.
class MessageReceivedUseCase
    extends BlocUseCase<RealtimeBloc, MessageReceivedEvent> {
  @override
  Future<void> execute(MessageReceivedEvent event) async {
    bloc.pushMessage(event.message);

    emitUpdate(
      newState: bloc.state.copyWith(
        lastMessage: event.message,
        messageCount: bloc.state.messageCount + 1,
      ),
      groupsToRebuild: {RealtimeGroups.message},
    );
  }
}
