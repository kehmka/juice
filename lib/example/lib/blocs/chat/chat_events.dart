import 'package:juice/juice.dart';

abstract class ChatEvent extends EventBase {}

class SendMessageEvent extends ChatEvent {
  final String message;

  SendMessageEvent({required this.message});
}

class ReceiveMessageEvent extends ChatEvent {
  final String message;

  ReceiveMessageEvent({required this.message});
}

class ConnectWebSocketEvent extends EventBase {
  ConnectWebSocketEvent();
}
