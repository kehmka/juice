import 'package:juice/juice.dart';
import 'package:juice_flags/juice_flags.dart';

import 'demo_flags_source.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  BlocScope.register<FlagsBloc>(
    () => FlagsBloc.withConfig(
      FlagsConfig(
        source: DemoFlagsSource(),
        // Safe baseline — reads resolve to these before/independent of fetch.
        defaults: {
          'new_layout': false,
          'promo_banner': false,
          'max_items': 10,
          'greeting': 'Hi',
        },
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
      title: 'juice_flags demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
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
      appBar: AppBar(title: const Text('juice_flags demo')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Rebuilds only when 'promo_banner' flips (every 3s via the stream).
          PromoBanner(),
          const SizedBox(height: 16),
          // Rebuilds only when 'greeting' or 'max_items' change.
          GreetingCard(),
          const SizedBox(height: 24),
          // Rebuilds only on the layout flag + an override toggle.
          LayoutToggle(),
        ],
      ),
    );
  }
}

class PromoBanner extends StatelessJuiceWidget<FlagsBloc> {
  PromoBanner({super.key}) : super(groups: {FlagsGroups.flag('promo_banner')});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    if (!bloc.boolFlag('promo_banner')) return const SizedBox.shrink();
    return Card(
      color: Colors.teal.shade100,
      child: const ListTile(
        leading: Icon(Icons.campaign),
        title: Text('Limited-time promo!'),
        subtitle: Text('This banner is gated on the promo_banner flag.'),
      ),
    );
  }
}

class GreetingCard extends StatelessJuiceWidget<FlagsBloc> {
  GreetingCard({super.key})
      : super(groups: {FlagsGroups.flag('greeting'), FlagsGroups.flag('max_items')});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Card(
      child: ListTile(
        title: Text('${bloc.stringFlag('greeting')} 👋'),
        subtitle: Text('max_items = ${bloc.intFlag('max_items')}'),
      ),
    );
  }
}

class LayoutToggle extends StatelessJuiceWidget<FlagsBloc> {
  LayoutToggle({super.key}) : super(groups: {FlagsGroups.flag('new_layout')});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final on = bloc.boolFlag('new_layout');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('new_layout (local override)'),
          value: on,
          onChanged: (v) => bloc.setFlagOverride('new_layout', v),
        ),
        Text(on ? 'Rendering the NEW layout' : 'Rendering the OLD layout'),
      ],
    );
  }
}
