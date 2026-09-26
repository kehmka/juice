import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../juice_types.dart';

/// The #1 latent Juice bug (AGENTS.md §4): a use case snapshots
/// `bloc.state`, suspends at an `await`, then builds the new state from the
/// snapshot — clobbering whatever another event emitted during the await.
///
/// ```dart
/// final items = bloc.state.items;          // snapshot
/// final added = await source.create(e.x);  // another event may emit here
/// emitUpdate(newState: bloc.state.copyWith(items: [...items, added])); // ✗
/// ```
///
/// The heuristic is deliberately narrow — it reports only when ALL hold, in
/// the `execute` method of a `package:juice` `UseCase` subclass:
///
/// 1. a local variable is initialized from a chain rooted at `bloc.state`
///    (`bloc.state`, `bloc.state.items`, `bloc.state.items.where(..).toList()`,
///    or a spread copy `[...bloc.state.items]`), with no `await` in the
///    initializer;
/// 2. its type is the state itself (a `BlocState`) or a collection
///    (`Iterable`/`Map`) — the things a new state is rebuilt from. Scalars
///    (an id, a count used as a key) are deliberately out of scope;
/// 3. an `await` follows the declaration in the same function body;
/// 4. after that `await`, the variable is read inside the `newState:`
///    argument of `emitUpdate` / `emitWaiting` / `emitFailure` /
///    `emitCancel`;
/// 5. the variable is never reassigned (a refreshed `s = bloc.state` after
///    the await is the fix, not the bug).
///
/// Declarations, awaits, and emits inside closures are ignored; order is
/// textual. The rule cannot see the builder's concurrency mode: a
/// `sequential` event serializes only same-type events, so another event
/// type can still emit during the await. If the read is safe by design
/// (a deliberate rollback, or no other event touches that field), silence
/// it at the use with
/// `// ignore: juice_lint/juice_stale_read_across_await`.
class StaleReadAcrossAwait extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'juice_stale_read_across_await',
    "'{0}' was read from bloc.state before an await; building newState from "
        'it can clobber state another event emitted during the await.',
    correctionMessage:
        'Read bloc.state again after the await, or make the event '
        '`concurrency: EventConcurrency.sequential`.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  StaleReadAcrossAwait()
    : super(
        name: 'juice_stale_read_across_await',
        description:
            'A bloc.state snapshot taken before an await must not be emitted '
            'after it.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodDeclaration(this, _Visitor(this));
  }
}

const _emitNames = {'emitUpdate', 'emitWaiting', 'emitFailure', 'emitCancel'};

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final StaleReadAcrossAwait rule;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme != 'execute' || node.isStatic) return;
    if (!isJuiceSubclass(enclosingClassElement(node), 'UseCase')) return;

    final body = node.body;
    final scan = _BodyScanner(body);
    body.accept(scan);
    if (scan.snapshots.isEmpty || scan.awaitOffsets.isEmpty) return;

    for (final use in scan.uses) {
      final decl = scan.snapshots[use.element];
      if (decl == null) continue;
      if (scan.reassigned.contains(use.element)) continue;
      final crossesAwait = scan.awaitOffsets.any(
        (o) => o > decl.end && o < use.offset,
      );
      if (!crossesAwait) continue;
      rule.reportAtNode(use, arguments: [use.name]);
    }
  }
}

/// One pass over an `execute` body, skipping nested closures.
class _BodyScanner extends RecursiveAstVisitor<void> {
  _BodyScanner(this.body);

  final FunctionBody body;

  /// Snapshot locals → their declaration.
  final snapshots = <LocalVariableElement, VariableDeclaration>{};
  final awaitOffsets = <int>[];

  /// Reads of a local inside an emit's `newState:` argument.
  final uses = <SimpleIdentifier>[];
  final reassigned = <Element>{};

  int _newStateDepth = 0;

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A closure runs on its own schedule; its reads/awaits aren't ordered
    // with the body's.
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    super.visitVariableDeclaration(node);
    final element = node.declaredFragment?.element;
    final init = node.initializer;
    if (element is! LocalVariableElement || init == null) return;
    if (_containsAwait(init) || !_rootsInBlocState(init)) return;
    if (!_isSnapshotType(element.type)) return;
    snapshots[element] = node;
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    super.visitAwaitExpression(node);
    awaitOffsets.add(node.offset);
  }

  @override
  void visitForElement(ForElement node) {
    super.visitForElement(node);
    if (node.awaitKeyword != null) awaitOffsets.add(node.offset);
  }

  @override
  void visitForStatement(ForStatement node) {
    super.visitForStatement(node);
    if (node.awaitKeyword != null) awaitOffsets.add(node.offset);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    super.visitAssignmentExpression(node);
    final lhs = node.leftHandSide;
    if (lhs is SimpleIdentifier) {
      final e = lhs.element;
      if (e != null) reassigned.add(e);
    }
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    final isNewState = node.name.lexeme == 'newState' && _isEmitArgument(node);
    if (isNewState) _newStateDepth++;
    super.visitNamedArgument(node);
    if (isNewState) _newStateDepth--;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_newStateDepth > 0 && node.element is LocalVariableElement) {
      uses.add(node);
    }
  }

  static bool _isEmitArgument(NamedArgument node) {
    final list = node.parent;
    if (list is! ArgumentList) return false;
    // `emitUpdate` & co. are function-typed fields on UseCase, so a call
    // resolves to a FunctionExpressionInvocation (`emitUpdate(...)`) or,
    // through `this.`, one on a PropertyAccess.
    final function = switch (list.parent) {
      FunctionExpressionInvocation(:final function) => function,
      MethodInvocation(:final target, :final methodName)
          when target == null || target is ThisExpression =>
        methodName,
      _ => null,
    };
    final name = switch (function) {
      SimpleIdentifier(:final name) => name,
      PropertyAccess(:final target, :final propertyName)
          when target is ThisExpression =>
        propertyName.name,
      _ => null,
    };
    return name != null && _emitNames.contains(name);
  }
}

bool _containsAwait(Expression e) {
  final finder = _AwaitFinder();
  e.accept(finder);
  return finder.found;
}

class _AwaitFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitAwaitExpression(AwaitExpression node) => found = true;
}

/// Whether [e] is a chain rooted at the use case's `bloc.state` — property
/// reads, method calls, `!`, parentheses, indexing — or a collection literal
/// whose only elements are spreads of such chains.
bool _rootsInBlocState(Expression e) {
  Expression? cur = e;
  while (cur != null) {
    switch (cur) {
      case PrefixedIdentifier(:final prefix, :final identifier):
        if (identifier.name == 'state' && _isBloc(prefix)) return true;
        return false;
      case PropertyAccess(:final target, :final propertyName):
        if (propertyName.name == 'state' && target != null && _isBloc(target)) {
          return true;
        }
        cur = target;
      case MethodInvocation(:final target):
        cur = target;
      case IndexExpression(:final target):
        cur = target;
      case PostfixExpression(:final operand):
        cur = operand;
      case ParenthesizedExpression(:final expression):
        cur = expression;
      case ListLiteral(:final elements):
        return _allSpreadsOfState(elements);
      case SetOrMapLiteral(:final elements):
        return _allSpreadsOfState(elements);
      default:
        return false;
    }
  }
  return false;
}

bool _allSpreadsOfState(List<CollectionElement> elements) =>
    elements.isNotEmpty &&
    elements.every(
      (el) => el is SpreadElement && _rootsInBlocState(el.expression),
    );

/// `bloc` or `this.bloc`, typed as a Juice bloc.
bool _isBloc(Expression e) {
  final isBlocName = switch (e) {
    SimpleIdentifier(:final name) => name == 'bloc',
    PropertyAccess(:final target, :final propertyName) =>
      target is ThisExpression && propertyName.name == 'bloc',
    _ => false,
  };
  return isBlocName && isJuiceType(e.staticType, 'JuiceBloc');
}

bool _isSnapshotType(DartType type) {
  if (isJuiceType(type, 'BlocState')) return true;
  if (type is! InterfaceType) return false;
  bool isCore(InterfaceElement el, String name) =>
      el.name == name && el.library.isDartCore;
  final el = type.element;
  if (isCore(el, 'Iterable') || isCore(el, 'Map')) return true;
  return el.allSupertypes.any(
    (t) => isCore(t.element, 'Iterable') || isCore(t.element, 'Map'),
  );
}
