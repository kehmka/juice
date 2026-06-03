import 'package:juice/juice.dart';
import 'package:juice_lifecycle/juice_lifecycle.dart';

/// Shows the live app-lifecycle phase, bound to [LifecycleBloc].
class HomeScreen extends StatelessJuiceWidget<LifecycleBloc> {
  HomeScreen({super.key}) : super(groups: {LifecycleGroups.state});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;
    final foreground = state.isForeground;

    return Scaffold(
      appBar: AppBar(title: const Text('juice_lifecycle demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              foreground ? Icons.visibility : Icons.visibility_off,
              size: 96,
              color: foreground ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              state.lifecycle.name,
              key: const Key('phase'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('previous: ${state.previous?.name ?? '—'}'),
            const SizedBox(height: 24),
            const Text('(the demo provider cycles every 2s)'),
          ],
        ),
      ),
    );
  }
}
