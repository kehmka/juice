import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../juice_types.dart';

/// BlocState is an immutable value: every change goes through `copyWith`.
/// A non-final instance field lets state be mutated in place, which breaks
/// equality-based diffing (skipIfSame) and the whole event-in/state-out
/// contract. Make the field `final`. (AGENTS.md: state holds data.)
///
/// Quick fix: `AddFinalToStateField` inserts `final`.
class MutableStateField extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'juice_mutable_state_field',
    'A BlocState field must be final — state is an immutable value '
        'changed only through copyWith.',
    correctionMessage: 'Add `final` and update via copyWith.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  MutableStateField()
    : super(
        name: 'juice_mutable_state_field',
        description: 'BlocState instance fields must be final.',
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

  final MutableStateField rule;

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (node.isStatic) return;
    if (node.fields.isFinal || node.fields.isConst) return;
    if (!isJuiceSubclass(enclosingClassElement(node), 'BlocState')) return;
    rule.reportAtNode(node);
  }
}
