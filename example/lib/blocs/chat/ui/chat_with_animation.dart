import 'package:juice/juice.dart';
import '../chat.dart';
import 'chat_list.dart';

class ChatWithAnimation extends StatefulWidget {
  const ChatWithAnimation({super.key});

  @override
  JuiceWidgetState<ChatBloc, ChatWithAnimation> createState() =>
      _ChatWithAnimationState();
}

class _ChatWithAnimationState
    extends JuiceWidgetState<ChatBloc, ChatWithAnimation>
    with TickerProviderStateMixin {
  _ChatWithAnimationState() : super(groups: const {"messages"});

  // Multiple animation controllers for different animations
  late AnimationController _messageController;
  late AnimationController _typingController;
  late AnimationController _connectionController;

  // Animations
  late Animation<Offset> _slideInFromRight;
  late Animation<Offset> _slideInFromLeft;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // Typing indicator animations
  late List<Animation<double>> _typingDots;

  late TextEditingController _textController;
  int _lastMessageIndex = -1;
  bool _isTyping = false;

  @override
  void onInit() {
    super.onInit();
    _lastMessageIndex = bloc.state.messages.length - 1;

    // Message animation setup
    _messageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Create two slide animations, one for sent and one for received messages
    _slideInFromRight = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _messageController,
      curve: Curves.easeOutCubic,
    ));

    _slideInFromLeft = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _messageController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _messageController,
      curve: Curves.easeOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _messageController,
      curve: Curves.easeOutBack,
    ));

    // Typing indicator setup
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _typingDots = List.generate(3, (index) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _typingController,
          curve: Interval(
            index * 0.2,
            0.6 + index * 0.2,
            curve: Curves.easeInOut,
          ),
        ),
      );
    });

    // Connection status animation
    _connectionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _textController = TextEditingController();
  }

  @override
  bool onStateChange(StreamStatus status) {
    if (status.event is ReceiveMessageEvent ||
        status.event is SendMessageEvent) {
      final newMessageIndex = bloc.state.messages.length - 1;

      if (newMessageIndex > _lastMessageIndex) {
        _lastMessageIndex = newMessageIndex;
        _messageController.forward(from: 0.0);
      }
    }

    // Handle connection status changes
    if (bloc.state.isConnected) {
      _connectionController.forward();
    } else {
      _connectionController.reverse();
    }

    return true;
  }

  @override
  void dispose() {
    _messageController.dispose();
    _typingController.dispose();
    _connectionController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      children: [
        _buildConnectionStatus(),
        Expanded(
          child: Stack(
            children: [
              ChatList(),
              if (_lastMessageIndex >= 0)
                _buildAnimatedMessage(bloc.state.messages[_lastMessageIndex]),
            ],
          ),
        ),
        if (status is WaitingStatus) _buildTypingIndicator(),
        if (status is FailureStatus) _buildErrorMessage(),
        _buildInputField(),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    return AnimatedBuilder(
      animation: _connectionController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          color: Color.lerp(
            Colors.red[100],
            Colors.green[100],
            _connectionController.value,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.scale(
                scale: 0.8 + (_connectionController.value * 0.2),
                child: Icon(
                  bloc.state.isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: Color.lerp(
                    Colors.red,
                    Colors.green,
                    _connectionController.value,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                bloc.state.isConnected
                    ? 'Connected to WebSocket Echo Server'
                    : 'Disconnected',
                style: TextStyle(
                  color: Color.lerp(
                    Colors.red,
                    Colors.green,
                    _connectionController.value,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Echo Server is typing"),
          const SizedBox(width: 12),
          ...List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _typingDots[index],
              builder: (context, child) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color:
                        Colors.blue.withValues(alpha: _typingDots[index].value),
                    shape: BoxShape.circle,
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAnimatedMessage(String message) {
    bool isSentMessage = message.startsWith("Sent:");

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: isSentMessage ? _slideInFromRight : _slideInFromLeft,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: _buildMessageBubble(message, isSentMessage),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(String message, bool isSentMessage) {
    return Container(
      margin: EdgeInsets.only(
        left: isSentMessage ? 32.0 : 16.0,
        right: isSentMessage ? 16.0 : 32.0,
        bottom: 8.0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 12.0,
      ),
      decoration: BoxDecoration(
        color: isSentMessage ? Colors.blue[100] : Colors.grey[100],
        borderRadius: BorderRadius.circular(20.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 16,
          color: isSentMessage ? Colors.blue[900] : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[700]),
          const SizedBox(width: 12),
          Text(
            "Failed to reach Echo Server",
            style: TextStyle(
              color: Colors.red[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8.0,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              onChanged: (value) {
                setState(() => _isTyping = value.isNotEmpty);
              },
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  bloc.send(SendMessageEvent(message: value));
                  _textController.clear();
                  setState(() => _isTyping = false);
                }
              },
              decoration: InputDecoration(
                hintText: 'Type a message',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24.0),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 12.0,
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isTyping
                  ? () {
                      bloc.send(
                          SendMessageEvent(message: _textController.text));
                      _textController.clear();
                      setState(() => _isTyping = false);
                    }
                  : null,
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(left: 8.0),
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: _isTyping ? Colors.blue : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send,
                  color: _isTyping ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
