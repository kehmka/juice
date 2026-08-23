// The ErrorSeverity/ErrorReporter deprecations are forced by
// custom_lint_builder 0.8.1: LintCode takes ErrorSeverity and
// DartLintRule.run supplies an ErrorReporter. No non-deprecated
// path exists until custom_lint adopts the diagnostic API.
// ignore_for_file: deprecated_member_use
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart' show ErrorSeverity;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'juice_types.dart';

/// State holds DATA, not behavior. Callbacks, timers, subscriptions, vendor
/// handles, and controllers belong on the bloc or its config — a value type
/// that carries them can't be compared, copied, or safely rebuilt from.
/// (AGENTS.md gotcha #5.)
class BehaviorInState extends DartLintRule {
  const BehaviorInState() : super(code: _code);

  static const _code = LintCode(
    name: 'juice_behavior_in_state',
    problemMessage:
        'BlocState holds data, not behavior — move functions, timers, '
        'subscriptions, and controllers to the bloc or its config.',
    correctionMessage: 'Keep this on the bloc/config; state stays a value.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  static const _behaviorNames = {
    'Timer',
    'StreamSubscription',
    'StreamController',
  };

  @override
  void run(CustomLintResolver resolver, ErrorReporter reporter,
      CustomLintContext context) {
    context.registry.addFieldDeclaration((node) {
      if (node.isStatic) return;
      final classNode = node.thisOrAncestorOfType<ClassDeclaration>();
      final element = classNode?.declaredFragment?.element;
      if (element == null || !blocStateChecker.isSuperOf(element)) return;

      final type = node.fields.type?.type;
      if (type == null) return;
      if (type is FunctionType) {
        reporter.atNode(node, _code);
        return;
      }
      final name = type.element?.name;
      if (name == null) return;
      if (_behaviorNames.contains(name) ||
          name.endsWith('Controller') ||
          name.endsWith('Bloc')) {
        reporter.atNode(node, _code);
      }
    });
  }
}
