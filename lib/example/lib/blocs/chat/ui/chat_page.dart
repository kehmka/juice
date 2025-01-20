import 'package:flutter/material.dart';
// import 'chat_widget.dart';
import 'chat_with_animation.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: const ChatWithAnimation(), //ChatWidget()
    );
  }
}
