import 'package:juice/juice.dart';

/// Rebuild groups emitted by `FlagsBloc`.
///
/// The per-flag group is the heart of selective refresh: a widget bound to
/// `FlagsGroups.flag('new_checkout')` rebuilds **only** when that flag's value
/// changes. A fetch that updates 2 of 50 flags rebuilds only those 2 widgets.
abstract final class FlagsGroups {
  /// A specific flag's value changed. `FlagsGroups.flag('x')` → `flags:flag:x`.
  static String flag(String key) => 'flags:flag:$key';

  /// Any flag changed (for widgets that read across many flags).
  static const any = 'flags:any';

  /// Fetch lifecycle changed (loading / error / lastFetched).
  static const status = 'flags:status';

  /// Status-level groups. Per-flag groups are dynamic — reach them via [flag].
  static const all = {any, status};
}

/// Immutable flags state.
///
/// [values] is the resolved map (defaults overlaid by the latest fetch). Reads
/// always resolve to *something* — use the typed accessors on `FlagsBloc`.
class FlagsState extends BlocState {
  /// Resolved flag values, keyed by flag name.
  final Map<String, Object?> values;

  /// A fetch is in flight.
  final bool loading;

  /// Last fetch error, or null. Surfaced loudly; reads still fall back to
  /// last-known/defaults so a flag always resolves.
  final String? error;

  /// Whether at least one successful fetch has completed.
  final bool fetched;

  const FlagsState({
    this.values = const {},
    this.loading = false,
    this.error,
    this.fetched = false,
  });

  static const initial = FlagsState();

  FlagsState copyWith({
    Map<String, Object?>? values,
    bool? loading,
    Object? error = _unset,
    bool? fetched,
  }) {
    return FlagsState(
      values: values ?? this.values,
      loading: loading ?? this.loading,
      error: identical(error, _unset) ? this.error : error as String?,
      fetched: fetched ?? this.fetched,
    );
  }

  @override
  String toString() =>
      'FlagsState(${values.length} flags, loading: $loading, fetched: $fetched, error: $error)';
}

const Object _unset = Object();
