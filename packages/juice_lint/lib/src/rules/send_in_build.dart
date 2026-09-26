import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../juice_types.dart';

/// `build` / `onBuild` runs on every rebuild — and a rebuild is what an
/// emission causes. Sending an event from the build body therefore dispatches
/// on every frame the widget rebuilds, and an event whose use case emits into
/// the widget's own groups loops. Send from a callback (`onPressed:`), from
/// `initState`, or from the bloc's own initialization instead.
///
/// Flags a `.send(...)` / `.sendCancellable(...)` on a `JuiceBloc` that sits
/// DIRECTLY in a build method body. Calls inside a closure (a callback, a
/// `builder:` function) run later, not during build, and are not flagged.
class SendInBuild extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'juice_send_in_build',
    'Sending an event from build/onBuild dispatches it on every rebuild.',
    correctionMessage:
        'Send from a callback (onPressed:), initState, or the bloc\'s own '
        'initialization instead.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  SendInBuild()
    : super(
        name: 'juice_send_in_build',
        description: 'Do not send bloc events directly from a build method.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final SendInBuild rule;

  static const _sendNames = {'send', 'sendCancellable'};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!_sendNames.contains(node.methodName.name)) return;
    final target = node.realTarget;
    if (target == null) return;
    if (!isJuiceType(target.staticType, 'JuiceBloc')) return;
    if (enclosingBuildBody(node) == null) return;
    rule.reportAtNode(node);
  }
}
