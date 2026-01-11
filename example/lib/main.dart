import 'package:juice/juice.dart';

import 'blocs/auth/ui/auth_page.dart';
import 'blocs/features_showcase/ui/features_showcase_page.dart';
import 'blocs/file_upload/src/ui/file_upload_page.dart';
import 'blocs/chat/ui/chat_page.dart';
import 'blocs/counter/ui/counter_page.dart';
import 'blocs/counter/ui/counter_builder_page.dart';
import 'blocs/form/ui/form_page.dart';
import 'blocs/todo/ui/todo_page.dart';
import 'blocs/weather/ui/weather_page.dart';
import 'blocs/blocs.dart';
import 'config/bloc_registration.dart';

// Example routes definition
final exampleRoutes = {
  '/auth': (context) => const AuthPage(),
  '/counter': (context) => const CounterPage(),
  '/counter-builder': (context) => const CounterBuilderPage(),
  '/features-showcase': (context) => const FeaturesShowcasePage(),
  '/todo': (context) => const TodoPage(),
  '/chat': (context) => const ChatPage(),
  '/form': (context) => const FormPage(),
  '/relay-demo': (context) => const RelayDemoPage(),
  '/weather': (context) => const WeatherPage(),
  '/upload': (context) => const FileUploadPage(),
  '/onboard': (context) => OnboardingScreen(),
  '/lifecycle-demo': (context) => const LifecycleDemoPage(),
};

void main() {
  // Initialize bloc registrations with lifecycle management
  BlocRegistry.initialize(ExampleDeepLinkConfig.config);

  // Get initial deep link if any
  final args = Uri.base.queryParameters;
  final initialExample = args['example'];

  runApp(MyApp(initialExample: initialExample));
}

class MyApp extends StatefulWidget {
  final String? initialExample;

  const MyApp({super.key, this.initialExample});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    // Handle initial deep link after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialExample != null) {
        // Use BlocScope.get for permanent blocs
        final appBloc = BlocScope.get<AppBloc>();
        appBloc.send(UpdateEvent(
          aviatorName: 'deepLink',
          aviatorArgs: {'deepLink': widget.initialExample},
        ));
      }
    });
  }

  @override
  void dispose() {
    // Clean up all blocs on app shutdown
    BlocScope.endAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: BlocScope.get<AppBloc>().navigatorKey,
      title: 'Juice Examples',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // Handle both initial route and deep links
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(
            builder: (context) => const MyHomePage(title: 'Juice Examples'),
          );
        }

        // Find matching example route
        final builder = exampleRoutes[settings.name];
        if (builder != null) {
          return MaterialPageRoute(
            builder: (context) => builder(context),
          );
        }

        // Handle unknown routes
        return MaterialPageRoute(
          builder: (context) => const MyHomePage(title: 'Juice Examples'),
        );
      },
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final examples = [
      {
        'title': 'New Features Showcase',
        'route': '/features-showcase',
        'subtitle': 'JuiceSelector, sendAndWait, JuiceException, LeakDetector'
      },
      {
        'title': 'Lifecycle Demo',
        'route': '/lifecycle-demo',
        'subtitle': 'LifecycleBloc cleanup with parallel tasks'
      },
      {'title': 'Auth & EventSubscription', 'route': '/auth'},
      {'title': 'Counter Example', 'route': '/counter'},
      {'title': 'Counter (Builder Pattern)', 'route': '/counter-builder'},
      {'title': 'StateRelay & StatusRelay Demo', 'route': '/relay-demo'},
      {'title': 'Todo Example', 'route': '/todo'},
      {'title': 'Chat Example', 'route': '/chat'},
      {'title': 'Form Example', 'route': '/form'},
      {'title': 'Weather Example', 'route': '/weather'},
      {'title': 'File Upload', 'route': '/upload'},
      {'title': 'Onboard example', 'route': '/onboard'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        itemCount: examples.length,
        itemBuilder: (context, index) {
          final example = examples[index];
          final subtitle = example['subtitle'] as String?;
          return ListTile(
            title: Text(example['title'] as String),
            subtitle: subtitle != null ? Text(subtitle) : null,
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              Navigator.pushNamed(context, example['route'] as String);
            },
          );
        },
      ),
    );
  }
}

// Add DeepLinkAviator configuration
class ExampleDeepLinkConfig {
  static final config = DeepLinkConfig(
    authRoute: '/', // No auth needed for examples
    routes: {
      'auth': DeepLinkRoute(path: ['/auth']),
      'counter': DeepLinkRoute(path: ['/counter']),
      'features-showcase': DeepLinkRoute(path: ['/features-showcase']),
      'relay-demo': DeepLinkRoute(path: ['/relay-demo']),
      'todo': DeepLinkRoute(path: ['/todo']),
      'chat': DeepLinkRoute(path: ['/chat']),
      'form': DeepLinkRoute(path: ['/form']),
      'weather': DeepLinkRoute(path: ['/weather']),
      'upload': DeepLinkRoute(path: ['/upload']),
      'onboard': DeepLinkRoute(path: ['/onboard']),
      'lifecycle-demo': DeepLinkRoute(path: ['/lifecycle-demo']),
    },
  );
}
