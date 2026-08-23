// The ErrorSeverity/ErrorReporter deprecations are forced by
// custom_lint_builder 0.8.1: LintCode takes ErrorSeverity and
// DartLintRule.run supplies an ErrorReporter. No non-deprecated
// path exists until custom_lint adopts the diagnostic API.
// ignore_for_file: deprecated_member_use
import 'package:analyzer/error/error.dart' show ErrorSeverity;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'juice_types.dart';

/// Events are matched by EXACT runtime type: a `typeOfEvent: InitEvent`
/// builder never fires for `InitEvent<T>`. So a generic `EventBase` subclass
/// is a silent dead event. Keep events non-generic; pass typed data via a
/// `withConfig` factory or a typed field instead. (AGENTS.md gotcha #2.)
class GenericEvent extends DartLintRule {
  const GenericEvent() : super(code: _code);

  static const _code = LintCode(
    name: 'juice_generic_event',
    problemMessage:
        'A generic EventBase subclass never matches a typeOfEvent builder '
        '(events are matched by exact runtime type).',
    correctionMessage:
        'Remove the type parameters; pass typed data via a field or a '
        'withConfig factory instead.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(CustomLintResolver resolver, ErrorReporter reporter,
      CustomLintContext context) {
    context.registry.addClassDeclaration((node) {
      if (node.typeParameters == null) return;
      final element = node.declaredFragment?.element;
      if (element == null || !eventBaseChecker.isSuperOf(element)) return;
      reporter.atToken(node.name, _code);
    });
  }
}
