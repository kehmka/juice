import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

class InterceptorsScreen extends StatefulWidget {
  const InterceptorsScreen({super.key});

  @override
  State<InterceptorsScreen> createState() => _InterceptorsScreenState();
}

class _InterceptorsScreenState extends State<InterceptorsScreen> {
  final List<LogEntry> _logs = [];
  bool _loggingEnabled = true;
  bool _authEnabled = false;
  bool _timingEnabled = true;
  final String _fakeToken = 'demo-jwt-token-12345';

  void _addLog(String message, LogType type) {
    setState(() {
      _logs.insert(0, LogEntry(
        message: message,
        type: type,
        timestamp: DateTime.now(),
      ));
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  Future<void> _reconfigureInterceptors() async {
    final fetchBloc = BlocScope.get<FetchBloc>();

    final interceptors = <FetchInterceptor>[];

    if (_timingEnabled) {
      interceptors.add(TimingInterceptor());
    }

    if (_loggingEnabled) {
      interceptors.add(LoggingInterceptor(
        logger: (msg) => _addLog(msg, LogType.info),
        logBody: true,
        logHeaders: _authEnabled, // Show headers when auth is enabled
      ));
    }

    if (_authEnabled) {
      interceptors.add(AuthInterceptor(
        tokenProvider: () async => _fakeToken,
        prefix: 'Bearer ',
      ));
    }

    await fetchBloc.send(ReconfigureInterceptorsEvent(
      interceptors: interceptors,
    ));

    _addLog('Interceptors configured: ${interceptors.map((i) => i.runtimeType.toString()).join(', ')}', LogType.system);
  }

  @override
  void initState() {
    super.initState();
    // Configure interceptors after the first frame to avoid racing with app init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reconfigureInterceptors();
    });
  }

  void _makeRequest() {
    final fetchBloc = BlocScope.get<FetchBloc>();
    fetchBloc.send(GetEvent(
      url: '/posts/1',
      cachePolicy: CachePolicy.networkOnly,
      decode: (raw) => raw,
    ));
  }

  void _makeFailingRequest() {
    final fetchBloc = BlocScope.get<FetchBloc>();
    fetchBloc.send(GetEvent(
      url: '/nonexistent/endpoint/404',
      cachePolicy: CachePolicy.networkOnly,
      decode: (raw) => raw,
    ));
  }

  void _clearLogs() {
    setState(() => _logs.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interceptors Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearLogs,
            tooltip: 'Clear Logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // Configuration Card
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
                    value: _timingEnabled,
                    dense: true,
                    onChanged: (v) {
                      setState(() => _timingEnabled = v);
                      _reconfigureInterceptors();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('LoggingInterceptor'),
                    subtitle: const Text('Logs requests and responses'),
                    value: _loggingEnabled,
                    dense: true,
                    onChanged: (v) {
                      setState(() => _loggingEnabled = v);
                      _reconfigureInterceptors();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('AuthInterceptor'),
                    subtitle: Text('Adds Bearer token: ${_fakeToken.substring(0, 15)}...'),
                    value: _authEnabled,
                    dense: true,
                    onChanged: (v) {
                      setState(() => _authEnabled = v);
                      _reconfigureInterceptors();
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _makeRequest,
                          icon: const Icon(Icons.send),
                          label: const Text('GET /posts/1'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _makeFailingRequest,
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

          // Logs Header
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
                  '${_logs.length} entries',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Logs List
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Make a request to see interceptor logs',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                log.timestamp.toIso8601String().substring(11, 23),
                                style: TextStyle(
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
                                  color: log.type.color,
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
}

enum LogType {
  info(Colors.cyan),
  error(Colors.red),
  system(Colors.yellow);

  final Color color;
  const LogType(this.color);
}

class LogEntry {
  final String message;
  final LogType type;
  final DateTime timestamp;

  LogEntry({
    required this.message,
    required this.type,
    required this.timestamp,
  });
}
