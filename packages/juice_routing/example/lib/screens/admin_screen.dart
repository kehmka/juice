import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

import '../auth_bloc.dart';

class AdminScreen extends StatelessJuiceWidget2<RoutingBloc, AuthBloc> {
  AdminScreen({super.key});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => bloc1.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.admin_panel_settings,
              size: 64,
              color: Colors.deepPurple,
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome, ${bloc2.state.username ?? 'Admin'}',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Card(
              color: Colors.orange[50],
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.shield, color: Colors.orange),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This route is protected by both AuthGuard and '
                        'RoleGuard. Non-admin users are blocked even if '
                        'they are authenticated.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
