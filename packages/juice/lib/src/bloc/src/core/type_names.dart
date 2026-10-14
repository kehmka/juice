import 'package:meta/meta.dart';

/// The display name of a [Type], memoized.
///
/// `Type.toString()` costs about as much as a quarter of a send; the
/// telemetry lines name a type several times per event. The set of types
/// a program dispatches is small and fixed, so the names are kept.
@internal
String typeName(Type type) => _names[type] ??= type.toString();

final _names = <Type, String>{};
