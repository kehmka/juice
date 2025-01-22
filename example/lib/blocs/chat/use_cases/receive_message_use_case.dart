import 'package:juice/juice.dart';
import '../chat.dart';

class ReceiveMessageUseCase extends BlocUseCase<ChatBloc, ReceiveMessageEvent> {
  @override
  Future<void> execute(ReceiveMessageEvent event) async {
    emitUpdate(
      groupsToRebuild: {"messages"},
      newState: bloc.state.copyWith(
        messages: [...bloc.state.messages, "Friend: ${event.message}"],
      ),
    );
  }
}
