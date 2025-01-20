import 'package:juice/example/lib/blocs/chat/use_cases/receive_message_use_case.dart';
import 'package:juice/juice.dart';
import 'chat.dart';
import '../../services/services.dart';
import '../chat/use_cases/initialize_websocket_use_case.dart';
import '../chat/use_cases/send_message_use_case.dart';

class ChatBloc extends JuiceBloc<ChatState> {
  ChatBloc(WebSocketService service)
      : super(
          ChatState(messages: [], lastError: "", isConnected: false),
          [
            () => StatefulUseCaseBuilder(
                  typeOfEvent: ConnectWebSocketEvent,
                  useCaseGenerator: () => InitializeWebSocketUseCase(service),
                  initialEventBuilder: () =>
                      ConnectWebSocketEvent(), // Startup event
                ),
            () => UseCaseBuilder(
                typeOfEvent: SendMessageEvent,
                useCaseGenerator: () => SendMessageUseCase(service)),
            () => UseCaseBuilder(
                typeOfEvent: ReceiveMessageEvent,
                useCaseGenerator: () => ReceiveMessageUseCase()),
          ],
          [],
        );
}
