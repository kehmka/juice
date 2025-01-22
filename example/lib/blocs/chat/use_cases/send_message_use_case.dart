import 'package:juice/juice.dart';
import '../chat.dart';
import '../../../services/services.dart';

class SendMessageUseCase extends BlocUseCase<ChatBloc, SendMessageEvent> {
  final WebSocketService _service;

  SendMessageUseCase(this._service);

  @override
  Future<void> execute(SendMessageEvent event) async {
    _service.sendMessage(event.message);
    emitUpdate(
      groupsToRebuild: {"messages"},
      newState: bloc.state.copyWith(
        messages: [...bloc.state.messages, "You: ${event.message}"],
      ),
    );
  }
}
