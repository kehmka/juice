import 'package:hive_ce/hive.dart';

/// Abstract interface for the Hive INITIALIZATION operations.
///
/// The seam the framework's own doctrine demands (AGENTS.md: anything
/// touching a vendor SDK sits behind an injected interface): Hive's init
/// surface is static, which left [InitializeUseCase]'s retry-on-stale-lock
/// behavior untestable (2026-09-01 — the fix shipped with an "honest note"
/// instead of a pin, which is a shortcut by another name).
///
/// **Note:** Gateways are internal implementation details. Public consumers
/// should use StorageBloc helpers or events.
abstract class HiveGateway {
  /// Initialize Hive at [path] (null = the platform default directory).
  Future<void> init(String? path);

  /// Whether a [TypeAdapter] with [typeId] is already registered.
  bool isAdapterRegistered(int typeId);

  /// Register a [TypeAdapter].
  void registerAdapter(TypeAdapter<dynamic> adapter);

  /// Open the named box and return its entry count.
  Future<int> openBox(String name);
}
