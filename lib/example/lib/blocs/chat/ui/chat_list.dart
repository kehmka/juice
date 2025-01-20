import 'package:juice/juice.dart';
import '../chat.dart';

class ChatList extends StatelessJuiceWidget<ChatBloc> {
  ChatList({super.key, super.groups = const {"messages"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return ListView.builder(
      itemCount: bloc.state.messages.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: Text(bloc.state.messages[index]),
        );
      },
    );
  }
}
