import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../juice_types.dart';

/// A lease is reference-counted ownership of a leased bloc: take it once in
/// `initState`, release it once in `dispose`. Taking one in `build` acquires
/// a new lease on every rebuild, none of them released — the bloc can never
/// be disposed.
///
/// Flags `BlocScope.lease(...)` / `BlocScope.leaseAsync(...)` from
/// `package:juice` that sits DIRECTLY in a build method body.
class LeaseInBuild extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'juice_lease_in_build',
    'BlocScope.lease in build/onBuild takes a new lease on every rebuild '
        'and never releases it.',
    correctionMessage: 'Take the lease in initState and release it in dispose.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  LeaseInBuild()
    : super(
        name: 'juice_lease_in_build',
        description: 'Do not take a BlocScope lease in a build method.',
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

  final LeaseInBuild rule;

  static const _leaseNames = {'lease', 'leaseAsync'};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!_leaseNames.contains(node.methodName.name)) return;
    final element = node.methodName.element;
    if (element is! MethodElement || !element.isStatic) return;
    if (!isJuiceClass(element.enclosingElement, 'BlocScope')) return;
    if (enclosingBuildBody(node) == null) return;
    rule.reportAtNode(node);
  }
}
