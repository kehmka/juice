/// The display name of a [Type], memoized.
///
/// `Type.toString()` is dear and the telemetry names a type several times
/// per event. The memo is a per-isolate map keyed by the [Type] object:
/// distinct instantiations of a generic are distinct keys, a hot reload
/// only adds entries, and the set of types a program dispatches is small
/// and fixed, so it never evicts.
String typeName(Type type) => _names[type] ??= type.toString();

final _names = <Type, String>{};
