import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'src/juice_panel.dart';

/// The Juice DevTools extension — BlocSignal tee-up item 1, phase 2.
///
/// A companion extension shipped inside `juice_observability`: it listens
/// to the `juice:<type>` extension events that `DevtoolsJuiceLogger` posts
/// (the framework's own structured telemetry, mirrored to the VM) and turns
/// them into a transitions timeline, use-case duration spans (paired by
/// `executionId`), a per-bloc view with the rebuild groups each emission
/// targeted, and a problems list (errors, unhandled events, leaks).
///
/// Source lives here (publish_to: none); the BUILT web app is copied into
/// `../juice_observability/extension/devtools/build` by
/// `dart run devtools_extensions build_and_copy --source=. --dest=../juice_observability/extension/devtools`.
void main() {
  runApp(const JuiceDevToolsExtension());
}

class JuiceDevToolsExtension extends StatelessWidget {
  const JuiceDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(child: JuicePanel());
  }
}
