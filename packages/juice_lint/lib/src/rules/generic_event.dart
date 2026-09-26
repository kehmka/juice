import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../juice_types.dart';

/// Events are matched by EXACT runtime type: a `typeOfEvent: InitEvent`
/// builder never fires for `InitEvent<T>`. So a generic `EventBase` subclass
/// is a silent dead event. Keep events non-generic; pass typed data via a
/// `withConfig` factory or a typed field instead. (AGENTS.md gotcha #2.)
///
/// Abstract and sealed generic bases (juice's own `ResultEvent<TResult>`)
/// are exempt: only their concrete subclasses are sent.
class GenericEvent extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'juice_generic_event',
    'A generic EventBase subclass never matches a typeOfEvent builder '
        '(events are matched by exact runtime type).',
    correctionMessage:
        'Remove the type parameters; pass typed data via a field or a '
        'withConfig factory instead.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  GenericEvent()
    : super(
        name: 'juice_generic_event',
        description: 'A generic EventBase subclass is a silent dead event.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addClassDeclaration(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final GenericEvent rule;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final namePart = node.namePart;
    if (namePart.typeParameters == null) return;
    // An abstract/sealed generic BASE is never sent itself — its concrete,
    // non-generic subclasses are (`class FetchUser extends ResultEvent<User>`).
    if (node.abstractKeyword != null || node.sealedKeyword != null) return;
    if (!isJuiceSubclass(node.declaredFragment?.element, 'EventBase')) return;
    rule.reportAtToken(namePart.typeName);
  }
}
