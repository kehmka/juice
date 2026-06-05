import 'package:juice/juice.dart';
import 'package:juice_realtime/juice_realtime.dart';

import 'demo_realtime.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo connector so the app runs with no server. In a real app:
  // RealtimeConfig(url: 'wss://your.host/ws').
  BlocScope.register<RealtimeBloc>(
    () => RealtimeBloc.withConfig(
      RealtimeConfig(connector: DemoRealtimeConnector()),
    ),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'juice_realtime demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('juice_realtime demo'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: StatusChip(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            LastMessageCard(),
            const Spacer(),
            SendBar(),
          ],
        ),
      ),
    );
  }
}

/// Connection status — rebuilds only on status changes.
class StatusChip extends StatelessJuiceWidget<RealtimeBloc> {
  StatusChip({super.key}) : super(groups: {RealtimeGroups.status});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final s = bloc.state.status;
    final (label, color) = switch (s) {
      RealtimeStatus.connected => ('connected', Colors.green),
      RealtimeStatus.connecting => ('connecting…', Colors.orange),
      RealtimeStatus.reconnecting =>
        ('reconnecting (#${bloc.state.reconnectAttempts})', Colors.orange),
      RealtimeStatus.disconnected => ('disconnected', Colors.red),
    };
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: TextStyle(color: color)),
    );
  }
}

/// Latest echoed message + count — rebuilds only on message arrival.
class LastMessageCard extends StatelessJuiceWidget<RealtimeBloc> {
  LastMessageCard({super.key}) : super(groups: {RealtimeGroups.message});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final m = bloc.state.lastMessage;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bolt),
        title: Text(m == null ? 'No messages yet' : '${m.data}'),
        subtitle: Text('${bloc.state.messageCount} received'),
      ),
    );
  }
}

class SendBar extends StatelessJuiceWidget<RealtimeBloc> {
  SendBar({super.key}) : super(groups: {RealtimeGroups.status});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final connected = bloc.state.isConnected;
    return Row(
      children: [
        Expanded(
          child: TextField(
            enabled: connected,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Type a message to echo',
            ),
            onSubmitted: connected ? (t) => bloc.sendMessage(t) : null,
          ),
        ),
        const SizedBox(width: 12),
        connected
            ? FilledButton.tonal(
                onPressed: bloc.disconnect, child: const Text('Disconnect'))
            : FilledButton(onPressed: bloc.connect, child: const Text('Connect')),
      ],
    );
  }
}
