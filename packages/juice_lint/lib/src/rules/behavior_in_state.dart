import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../juice_types.dart';

/// State holds DATA, not behavior. Callbacks, timers, subscriptions, vendor
/// handles, and controllers belong on the bloc or its config — a value type
/// that carries them can't be compared, copied, or safely rebuilt from.
/// (AGENTS.md gotcha #5.)
class BehaviorInState extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'juice_behavior_in_state',
    'BlocState holds data, not behavior — move functions, timers, '
        'subscriptions, and controllers to the bloc or its config.',
    correctionMessage: 'Keep this on the bloc/config; state stays a value.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  BehaviorInState()
    : super(
        name: 'juice_behavior_in_state',
        description:
            'BlocState fields must not hold functions, timers, '
            'subscriptions, controllers, or blocs.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addFieldDeclaration(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final BehaviorInState rule;

  static const _behaviorNames = {
    'Timer',
    'StreamSubscription',
    'StreamController',
  };

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (node.isStatic) return;
    if (!isJuiceSubclass(enclosingClassElement(node), 'BlocState')) return;

    final type = node.fields.type?.type;
    if (type == null) return;
    if (type is FunctionType) {
      rule.reportAtNode(node);
      return;
    }
    final name = type.element?.name;
    if (name == null) return;
    if (_behaviorNames.contains(name) ||
        name.endsWith('Controller') ||
        name.endsWith('Bloc')) {
      rule.reportAtNode(node);
    }
  }
}
