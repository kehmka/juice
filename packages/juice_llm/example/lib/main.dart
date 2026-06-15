import 'package:juice/juice.dart';
import 'package:juice_llm/juice_llm.dart';

// To run a REAL local model instead of the echo runtime, install Ollama
// (`ollama serve` + `ollama pull gemma3:1b`) and swap the provider below:
//
//   import 'ollama_llm_provider.dart';
//   ...provider: OllamaLlmProvider(model: 'gemma3:1b')...

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  BlocScope.register<LlmBloc>(
    // Echo runtime: streams a reflective reply word-by-word, no downloads,
    // runs on any platform. Swap in OllamaLlmProvider for a real model.
    () => LlmBloc.withConfig(LlmConfig(
      provider: EchoLlmProvider(perTokenDelay: const Duration(milliseconds: 60)),
    )),
    lifecycle: BlocLifecycle.permanent,
  );

  // The echo provider has no weights to fetch — load it straight to ready.
  BlocScope.get<LlmBloc>().loadModel(LlmModel(
    id: 'echo',
    displayName: 'Echo',
    source: Uri.parse('echo:reference'),
    sha256: '',
    sizeBytes: 0,
    capabilities: const {LlmCapability.text, LlmCapability.embeddings},
  ));

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'juice_llm demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFA8761B)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController(text: 'a quiet morning by the river');
  var _counter = 0;
  String? _currentId;

  void _generate() {
    final id = 'r${_counter++}';
    setState(() => _currentId = id);
    BlocScope.get<LlmBloc>().generate(LlmRequest(
      requestId: id,
      messages: [LlmMessage.user(_input.text)],
    ));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('juice_llm demo'),
        actions: [ModelChip(), const SizedBox(width: 12)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _input,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _generate(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate'),
                ),
                const SizedBox(width: 12),
                if (_currentId != null) CancelButton(requestId: _currentId!),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _currentId == null
                  ? const Center(child: Text('Generate to see streaming output'))
                  : GenerationView(requestId: _currentId!),
            ),
          ],
        ),
      ),
    );
  }
}

/// Model-status chip — rebuilds only on the model group.
class ModelChip extends StatelessJuiceWidget<LlmBloc> {
  ModelChip({super.key}) : super(groups: {LlmGroups.model});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final s = bloc.state.modelStatus;
    final ready = s == LlmModelStatus.ready;
    return Chip(
      avatar: Icon(ready ? Icons.bolt : Icons.hourglass_empty, size: 16),
      label: Text(s.name),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// The streaming output — rebuilds ONLY on this request's group, as tokens
/// arrive (throttled by the bloc).
class GenerationView extends StatelessJuiceWidget<LlmBloc> {
  GenerationView({super.key, required this.requestId})
      : super(groups: {LlmGroups.gen(requestId)});

  final String requestId;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final session = bloc.state.sessions[requestId];
    if (session == null) return const SizedBox.shrink();
    final streaming = session.status == SessionStatus.streaming;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(session.status.name.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall),
              if (streaming) ...[
                const SizedBox(width: 8),
                const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            session.text.isEmpty ? '…' : session.text,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (session.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(session.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

class CancelButton extends StatelessJuiceWidget<LlmBloc> {
  CancelButton({super.key, required this.requestId})
      : super(groups: {LlmGroups.gen(requestId)});

  final String requestId;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final session = bloc.state.sessions[requestId];
    final streaming = session?.status == SessionStatus.streaming;
    if (!streaming) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () => bloc.cancel(requestId),
      icon: const Icon(Icons.stop),
      label: const Text('Cancel'),
    );
  }
}
