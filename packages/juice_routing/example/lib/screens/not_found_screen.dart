import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

class NotFoundScreen extends StatelessJuiceWidget<RoutingBloc> {
  NotFoundScreen({super.key});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Not Found'),
        backgroundColor: Colors.red[100],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (bloc.state.canPop) {
              bloc.pop();
            } else {
              bloc.navigate('/');
            }
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 80,
                color: Colors.red,
              ),
              const SizedBox(height: 24),
              const Text(
                '404',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Page Not Found',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 16),
              const Text(
                'The route you requested does not exist.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => bloc.navigate('/'),
                icon: const Icon(Icons.home),
                label: const Text('Go Home'),
              ),
              const SizedBox(height: 12),
              if (bloc.state.canPop)
                OutlinedButton.icon(
                  onPressed: () => bloc.pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
