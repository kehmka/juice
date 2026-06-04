import 'package:juice/juice.dart';
import 'package:juice_notifications/juice_notifications.dart';

import 'demo_notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo service so the app runs with no plugin/timezone. Swap for
  // NotificationsConfig() (default LocalNotificationService) in a real app.
  BlocScope.register<NotificationsBloc>(
    () => NotificationsBloc.withConfig(
      NotificationsConfig(service: DemoNotificationService()),
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
      title: 'juice_notifications demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessJuiceWidget<NotificationsBloc> {
  HomeScreen({super.key}) : super(groups: NotificationsGroups.all);

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;
    final nextId = state.scheduled.length + 1;

    return Scaffold(
      appBar: AppBar(title: const Text('juice_notifications demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Permission granted'),
              subtitle: const Text('(wire from juice_permissions in a real app)'),
              value: state.permissionGranted,
              onChanged: bloc.setPermissionStatus,
            ),
            const Divider(),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: () => bloc.schedule(
                    JuiceNotification(
                      id: nextId,
                      title: 'Reminder #$nextId',
                      body: 'Scheduled from the demo',
                    ),
                    DateTime.now().add(const Duration(minutes: 1)),
                  ),
                  child: const Text('Schedule'),
                ),
                OutlinedButton(
                  onPressed: bloc.cancelAll,
                  child: const Text('Cancel all'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Scheduled (${state.scheduled.length})',
                style: Theme.of(context).textTheme.titleSmall),
            Expanded(
              child: ListView(
                children: [
                  for (final n in state.scheduled)
                    ListTile(
                      title: Text(n.title),
                      subtitle: Text(n.body),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => bloc.cancel(n.id),
                      ),
                    ),
                ],
              ),
            ),
            if (state.lastTap != null)
              Text('Last tap: id=${state.lastTap!.id}'),
          ],
        ),
      ),
    );
  }
}
