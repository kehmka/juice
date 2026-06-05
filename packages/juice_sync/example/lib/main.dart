import 'package:juice/juice.dart';
import 'package:juice_sync/juice_sync.dart';

import 'demo_sync.dart';

final _online = OnlineToggle();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo seams: in-memory store (NOT durable — real apps use StorageSyncStore),
  // a fake executor, and a manual online toggle.
  BlocScope.register<SyncBloc>(
    () => SyncBloc.withConfig(
      SyncConfig(
        store: InMemorySyncStore(),
        executor: DemoExecutor().call,
        onlineSignal: _online.stream,
        maxAttempts: 4,
        initialBackoff: const Duration(seconds: 1),
      ),
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
      title: 'juice_sync demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
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
        title: const Text('juice_sync — outbox'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: StatusBar(),
        ),
      ),
      body: QueueList(),
      floatingActionButton: EnqueueButtons(),
    );
  }
}

/// Status + online toggle — rebuilds only on `sync:status`.
class StatusBar extends StatelessJuiceWidget<SyncBloc> {
  StatusBar({super.key}) : super(groups: {SyncGroups.status});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final s = bloc.state;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12).copyWith(bottom: 6),
      child: Row(
        children: [
          Icon(s.online ? Icons.cloud_done : Icons.cloud_off,
              size: 18, color: s.online ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Text('${s.pendingCount} pending · ${s.failedCount} failed · '
              '${s.processedCount} sent'),
          const Spacer(),
          Switch(
            value: s.online,
            onChanged: (v) => _online.set(v),
          ),
        ],
      ),
    );
  }
}

/// The queue — rebuilds when membership changes (`sync:queue`/`sync:failed`).
class QueueList extends StatelessJuiceWidget<SyncBloc> {
  QueueList({super.key})
      : super(groups: {SyncGroups.queue, SyncGroups.failed});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final items = [...bloc.state.pending, ...bloc.state.failed];
    if (items.isEmpty) {
      return const Center(child: Text('Queue is empty — enqueue something →'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [for (final m in items) MutationTile(id: m.id)],
    );
  }
}

/// One mutation — rebuilds only on its own `sync:mutation:<id>`.
class MutationTile extends StatelessJuiceWidget<SyncBloc> {
  MutationTile({required this.id})
      : super(key: ValueKey(id), groups: {SyncGroups.mutation(id)});

  final String id;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final m = [...bloc.state.pending, ...bloc.state.failed]
        .where((x) => x.id == id)
        .firstOrNull;
    if (m == null) return const SizedBox.shrink();

    final (icon, color) = switch (m.status) {
      MutationStatus.pending => (Icons.schedule, Colors.orange),
      MutationStatus.inFlight => (Icons.sync, Colors.blue),
      MutationStatus.failed => (Icons.error, Colors.red),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(m.type),
        subtitle: Text(m.status == MutationStatus.failed
            ? 'failed: ${m.lastError}'
            : 'attempts: ${m.attempts}'),
        trailing: m.status == MutationStatus.failed
            ? IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => bloc.retryFailed(id))
            : IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => bloc.discard(id)),
      ),
    );
  }
}

class EnqueueButtons extends StatelessJuiceWidget<SyncBloc> {
  EnqueueButtons({super.key}) : super(groups: const {});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: 'ok',
          onPressed: () => bloc.enqueue('ok', {'at': 'now'}),
          icon: const Icon(Icons.add),
          label: const Text('ok'),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          heroTag: 'flaky',
          onPressed: () => bloc.enqueue('flaky', {}),
          child: const Text('flk'),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          heroTag: 'bad',
          backgroundColor: Colors.red.shade200,
          onPressed: () => bloc.enqueue('bad', {}),
          child: const Text('bad'),
        ),
      ],
    );
  }
}
