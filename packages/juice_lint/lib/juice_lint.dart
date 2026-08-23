import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/behavior_in_state.dart';
import 'src/generic_event.dart';
import 'src/mutable_state_field.dart';

/// custom_lint entrypoint. Add `juice_lint` as a dev_dependency and enable
/// the `custom_lint` analyzer plugin to get the Juice idioms as lints.
PluginBase createPlugin() => _JuiceLint();

class _JuiceLint extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
        const GenericEvent(),
        const MutableStateField(),
        const BehaviorInState(),
      ];
}
