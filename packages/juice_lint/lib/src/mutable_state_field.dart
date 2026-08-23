// The ErrorSeverity/ErrorReporter deprecations are forced by
// custom_lint_builder 0.8.1: LintCode takes ErrorSeverity and
// DartLintRule.run supplies an ErrorReporter. No non-deprecated
// path exists until custom_lint adopts the diagnostic API.
// ignore_for_file: deprecated_member_use
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show ErrorSeverity;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'juice_types.dart';

/// BlocState is an immutable value: every change goes through `copyWith`.
/// A non-final instance field lets state be mutated in place, which breaks
/// equality-based diffing (skipIfSame) and the whole event-in/state-out
/// contract. Make the field `final`. (AGENTS.md: state holds data.)
class MutableStateField extends DartLintRule {
  const MutableStateField() : super(code: _code);

  static const _code = LintCode(
    name: 'juice_mutable_state_field',
    problemMessage:
        'A BlocState field must be final — state is an immutable value '
        'changed only through copyWith.',
    correctionMessage: 'Add `final` and update via copyWith.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(CustomLintResolver resolver, ErrorReporter reporter,
      CustomLintContext context) {
    context.registry.addFieldDeclaration((node) {
      if (node.isStatic) return;
      if (node.fields.isFinal || node.fields.isConst) return;
      final classNode = node.thisOrAncestorOfType<ClassDeclaration>();
      final element = classNode?.declaredFragment?.element;
      if (element == null || !blocStateChecker.isSuperOf(element)) return;
      reporter.atNode(node, _code);
    });
  }
}
