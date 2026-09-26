import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/source_range.dart';

import '../juice_types.dart';

/// Every `UseCaseBuilder` should say how same-type events interleave. The
/// default, `concurrent`, lets a second event's use case run while the first
/// is suspended at an `await` — the read-before-await race (AGENTS.md §4).
/// Declaring the mode (`sequential` for shared-state mutation, `droppable`
/// for exclusive flows, `concurrent` for genuinely independent events) makes
/// the choice explicit and reviewable.
///
/// Flags `UseCaseBuilder(...)` and `UseCaseBuilder.typed(...)` from
/// `package:juice` with no `concurrency:` argument. Registered as a LINT
/// rule (opt-in): the `concurrent` default is legitimate for independent
/// events, so requiring the mode everywhere is a project policy.
class MissingConcurrencyMode extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'juice_missing_concurrency_mode',
    'This UseCaseBuilder does not declare a concurrency mode (it defaults '
        'to concurrent).',
    correctionMessage:
        'Pass `concurrency: EventConcurrency.sequential` (shared-state '
        'mutation), `.droppable` (exclusive flows), or `.concurrent` '
        '(independent events).',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  MissingConcurrencyMode()
    : super(
        name: 'juice_missing_concurrency_mode',
        description: 'Every UseCaseBuilder declares its concurrency mode.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addInstanceCreationExpression(this, visitor);
    registry.addMethodInvocation(this, visitor);
  }
}

bool _hasConcurrencyArg(ArgumentList args) => args.arguments.any(
  (a) => a is NamedArgument && a.name.lexeme == 'concurrency',
);

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final MissingConcurrencyMode rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName.element;
    if (constructor == null || constructor.isPrivate) return;
    if (!isJuiceClass(constructor.enclosingElement, 'UseCaseBuilder')) return;
    if (_hasConcurrencyArg(node.argumentList)) return;
    rule.reportAtNode(node.constructorName);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'typed') return;
    final element = node.methodName.element;
    if (element is! MethodElement || !element.isStatic) return;
    if (!isJuiceClass(element.enclosingElement, 'UseCaseBuilder')) return;
    if (_hasConcurrencyArg(node.argumentList)) return;
    final start = (node.target ?? node.methodName).offset;
    rule.reportAtSourceRange(SourceRange(start, node.methodName.end - start));
  }
}
