import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// The Juice base types the rules key on. Every check is scoped to the
/// framework's own declarations (a library under `package:juice/`), never a
/// same-named class from another package.

bool _isInPackage(LibraryElement? library, String package) {
  final uri = library?.uri;
  return uri != null &&
      uri.scheme == 'package' &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == package;
}

/// Whether [element] IS the `package:juice` class named [name].
bool isJuiceClass(Element? element, String name) =>
    element is InterfaceElement &&
    element.name == name &&
    _isInPackage(element.library, 'juice');

/// Whether [element] is a strict subtype of the `package:juice` class [name]
/// (the class itself does not count — the framework's own base is exempt).
bool isJuiceSubclass(Element? element, String name) =>
    element is InterfaceElement &&
    element.allSupertypes.any((t) => isJuiceClass(t.element, name));

/// Whether [type] is the `package:juice` class [name] or a subtype of it.
/// A type parameter is judged by its bound (`TBloc extends JuiceBloc`).
bool isJuiceType(DartType? type, String name) {
  var t = type;
  if (t is TypeParameterType) t = t.bound;
  if (t is! InterfaceType) return false;
  return isJuiceClass(t.element, name) || isJuiceSubclass(t.element, name);
}

/// The element of the class declaration enclosing [node], if any.
InterfaceElement? enclosingClassElement(AstNode node) =>
    node.thisOrAncestorOfType<ClassDeclaration>()?.declaredFragment?.element;

/// Whether [method] is a Flutter build method: named `build` or `onBuild`
/// (Juice widgets) with a `BuildContext` from `package:flutter` as its first
/// parameter. The parameter check keeps a `build()` on a plain builder or
/// config class out of scope.
bool isBuildMethod(MethodDeclaration method) {
  final name = method.name.lexeme;
  if (name != 'build' && name != 'onBuild') return false;
  final params = method.parameters?.parameters;
  if (params == null || params.isEmpty) return false;
  final type = params.first.declaredFragment?.element.type;
  return type is InterfaceType &&
      type.element.name == 'BuildContext' &&
      _isInPackage(type.element.library, 'flutter');
}

/// The build method whose body DIRECTLY contains [node] — `null` when [node]
/// sits inside a closure or local function (an `onPressed:` callback, a
/// `builder:` function), which runs later, not during build.
MethodDeclaration? enclosingBuildBody(AstNode node) {
  for (AstNode? n = node.parent; n != null; n = n.parent) {
    if (n is FunctionExpression) return null;
    if (n is MethodDeclaration) return isBuildMethod(n) ? n : null;
    if (n is CompilationUnitMember) return null;
  }
  return null;
}
