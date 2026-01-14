import 'package:juice/juice.dart';

import '../blocs/blocs.dart';

class InterceptorsScreen extends StatelessJuiceWidget<InterceptorsBloc> {
  InterceptorsScreen({super.key});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Interceptors Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => bloc.send(ClearLogsEvent()),
            tooltip: 'Clear Logs',
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Interceptors',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('TimingInterceptor'),
                    subtitle: const Text('Adds request duration tracking'),
                    value: state.timingEnabled,
                    dense: true,
                    onChanged: (v) {
                      bloc.send(ToggleTimingEvent(v));
                      bloc.send(ConfigureInterceptorsEvent());
                    },
                  ),
                  SwitchListTile(
                    title: const Text('LoggingInterceptor'),
                    subtitle: const Text('Logs requests and responses'),
                    value: state.loggingEnabled,
                    dense: true,
                    onChanged: (v) {
                      bloc.send(ToggleLoggingEvent(v));
                      bloc.send(ConfigureInterceptorsEvent());
                    },
                  ),
                  SwitchListTile(
                    title: const Text('AuthInterceptor'),
                    subtitle: Text(
                        'Adds Bearer token: ${state.fakeToken.substring(0, 15)}...'),
                    value: state.authEnabled,
                    dense: true,
                    onChanged: (v) {
                      bloc.send(ToggleAuthEvent(v));
                      bloc.send(ConfigureInterceptorsEvent());
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => bloc.send(MakeRequestEvent()),
                          icon: const Icon(Icons.send),
                          label: const Text('GET /posts/1'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => bloc.send(MakeFailingRequestEvent()),
                          icon: const Icon(Icons.error_outline),
                          label: const Text('GET /404'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Interceptor Logs',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '${state.logs.length} entries',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: state.logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Make a request to see interceptor logs',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: state.logs.length,
                      itemBuilder: (context, index) {
                        final log = state.logs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                log.timestamp.toIso8601String().substring(11, 23),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  color: Colors.white38,
                                ),
                              ),
                              Text(
                                log.message,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: _logColor(log.type),
                                ),
                              ),
                              const Divider(color: Colors.white12, height: 12),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Color _logColor(LogType type) {
    switch (type) {
      case LogType.info:
        return Colors.cyan;
      case LogType.error:
        return Colors.red;
      case LogType.system:
        return Colors.yellow;
    }
  }
}
