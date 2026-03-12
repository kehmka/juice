import 'package:juice/juice.dart';
import '../chat_bloc.dart';
import '../chat_events.dart';

class UpdateTypingUseCase extends UseCase<ChatBloc, UpdateTypingEvent> {
  @override
  Future<void> execute(UpdateTypingEvent event) async {
    if (event.contactId == bloc.state.activeContactId) {
      emitUpdate(
        newState: bloc.state.copyWith(peerIsTyping: event.isTyping),
      );
    }
  }
}
