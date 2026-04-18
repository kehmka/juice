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
  late final AppBloc _appBloc;

  @override
  void initState() {
    super.initState();
    _appBloc = BlocScope.get<AppBloc>();

    // Handle initial deep link after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialExample != null) {
        _appBloc.send(UpdateEvent(
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
      navigatorKey: _appBloc.navigatorKey,
      title: 'Juice Showcase',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // Handle both initial route and deep links
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(
            builder: (context) => const MyHomePage(title: 'Juice Showcase'),
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
          builder: (context) => const MyHomePage(title: 'Juice Showcase'),
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
        'title': 'Framework Features Showcase',
        'route': '/features-showcase',
        'subtitle': 'Selectors, sendAndWait, typed failures, rebuild tracking'
      },
      {
        'title': 'Lifecycle Demo',
        'route': '/lifecycle-demo',
        'subtitle':
            'FeatureScope cleanup, barriers, notifications, leak detection'
      },
      {
        'title': 'Auth & EventSubscription',
        'route': '/auth',
        'subtitle': 'Leased profile bloc reacting to auth events'
      },
      {
        'title': 'StateRelay & StatusRelay Demo',
        'route': '/relay-demo',
        'subtitle': 'Cross-bloc communication without widget glue'
      },
      {
        'title': 'Counter Example',
        'route': '/counter',
        'subtitle': 'Leased screen-owned state with targeted rebuilds'
      },
      {
        'title': 'Counter (Builder Pattern)',
        'route': '/counter-builder',
        'subtitle': 'Inline builder composition without widget inheritance'
      },
      {
        'title': 'Todo Example',
        'route': '/todo',
        'subtitle': 'Leased list state for a screen-local workflow'
      },
      {
        'title': 'Chat Example',
        'route': '/chat',
        'subtitle': 'Leased real-time screen using stateful widget ownership'
      },
      {
        'title': 'Form Example',
        'route': '/form',
        'subtitle': 'Leased form workflow and async submission feedback'
      },
      {
        'title': 'Weather Example',
        'route': '/weather',
        'subtitle': 'Leased feature state plus permanent settings state'
      },
      {
        'title': 'File Upload',
        'route': '/upload',
        'subtitle': 'Leased upload state with progress-oriented UI'
      },
      {
        'title': 'Onboarding Example',
        'route': '/onboard',
        'subtitle': 'Leased page-flow state owned by the screen'
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Showcase App',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'This app is the fast tour of Juice concepts. For the strongest production-style references, start with packages/juice_examples, especially notes_app, social_feed, dashboard, and ecommerce.',
                  ),
                ],
              ),
            ),
          ),
          ...examples.map((example) {
            final subtitle = example['subtitle'] as String?;
            return ListTile(
              title: Text(example['title'] as String),
              subtitle: subtitle != null ? Text(subtitle) : null,
              trailing: const Icon(Icons.arrow_forward),
              onTap: () {
                Navigator.pushNamed(context, example['route'] as String);
              },
            );
          }),
        ],
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
