import 'package:juice/juice.dart';
import 'package:juice_connectivity/juice_connectivity.dart';

/// Shows live connectivity, bound to [ConnectivityBloc] via rebuild groups.
class HomeScreen extends StatelessJuiceWidget<ConnectivityBloc> {
  HomeScreen({super.key}) : super(groups: ConnectivityGroups.all);

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;
    final online = state.isOnline;

    return Scaffold(
      appBar: AppBar(title: const Text('juice_connectivity demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              online ? Icons.wifi : Icons.wifi_off,
              size: 96,
              color: online ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              online ? 'Online' : 'Offline',
              key: const Key('status'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('Connection: ${state.connectionType.name}'),
            const SizedBox(height: 24),
            const Text('(the demo provider cycles every 3s)'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => bloc.check(),
              child: const Text('Check now'),
            ),
          ],
        ),
      ),
    );
  }
}
