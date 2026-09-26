// Fixtures for juice_lint's widget rules: juice_send_in_build and
// juice_lease_in_build. Same `// expect_lint:` convention as fixtures.dart.
import 'package:juice/juice.dart';

import 'use_case_fixtures.dart';

// --- juice_send_in_build ----------------------------------------------------

class ItemsView extends StatelessJuiceWidget<ItemsBloc> {
  ItemsView({super.key}) : super(groups: {ItemsGroups.list});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // expect_lint: juice_send_in_build
    bloc.send(RefreshEvent()); // dispatches on every rebuild
    if (bloc.state.items.isEmpty) {
      // expect_lint: juice_send_in_build
      bloc.send(SelectEvent()); // still directly in the build body
    }
    return GestureDetector(
      onTap: () => bloc.send(AddItemEvent('x')), // a callback → fine
      child: Builder(
        builder: (context) => Text('${bloc.state.items.length}'), // fine
      ),
    );
  }
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  // --- juice_lease_in_build ------------------------------------------------
  late final BlocLease<ItemsBloc> _lease;

  @override
  void initState() {
    super.initState();
    _lease = BlocScope.lease<ItemsBloc>(); // initState → fine
    _lease.bloc.send(RefreshEvent()); // not build → fine
  }

  @override
  void dispose() {
    _lease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // expect_lint: juice_lease_in_build
    final lease = BlocScope.lease<ItemsBloc>(); // a new lease per rebuild
    return TextButton(
      onPressed: () => _lease.bloc.send(SaveEvent()), // a callback → fine
      child: Text('${lease.bloc.state.count}'),
    );
  }
}

/// A `build()` that is not a widget build (no BuildContext) is out of scope.
class RequestBuilder {
  final ItemsBloc bloc;
  RequestBuilder(this.bloc);

  void build() => bloc.send(RefreshEvent());
}
