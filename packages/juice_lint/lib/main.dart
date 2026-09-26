/// juice_lint — the Juice AGENTS.md idioms as analyzer rules.
///
/// An `analysis_server_plugin` plugin: the analysis server imports this
/// library and reads the top-level [plugin]. Enable it with a top-level
/// `plugins:` section in `analysis_options.yaml`; its diagnostics are then
/// reported by the IDE and `dart analyze`.
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/fixes/add_final_to_state_field.dart';
import 'src/rules/behavior_in_state.dart';
import 'src/rules/generic_event.dart';
import 'src/rules/lease_in_build.dart';
import 'src/rules/missing_concurrency_mode.dart';
import 'src/rules/mutable_state_field.dart';
import 'src/rules/send_in_build.dart';
import 'src/rules/stale_read_across_await.dart';

/// The plugin instance the analysis server loads.
final plugin = JuiceLintPlugin();

/// Registers the juice_lint rules and quick fixes.
///
/// Warning rules are on by default (turn one off with `rule: false` under
/// `plugins: juice_lint: diagnostics:`). `juice_missing_concurrency_mode` is
/// a policy rule — "every builder declares its mode" — so it is a lint rule,
/// off until enabled with `juice_missing_concurrency_mode: true`.
class JuiceLintPlugin extends Plugin {
  @override
  String get name => 'juice_lint';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(GenericEvent())
      ..registerWarningRule(MutableStateField())
      ..registerWarningRule(BehaviorInState())
      ..registerWarningRule(SendInBuild())
      ..registerWarningRule(LeaseInBuild())
      ..registerWarningRule(StaleReadAcrossAwait())
      ..registerLintRule(MissingConcurrencyMode())
      ..registerFixForRule(MutableStateField.code, AddFinalToStateField.new);
  }
}
