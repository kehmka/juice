import 'package:hive_ce_flutter/hive_flutter.dart';

import 'hive_adapter.dart';
import 'hive_gateway.dart';

/// The shipped [HiveGateway]: thin forwarding onto Hive's statics and the
/// package's own [HiveAdapterFactory]. No logic — logic lives in the use
/// case, where the fake can reach it.
class HiveGatewayImpl implements HiveGateway {
  const HiveGatewayImpl();

  @override
  Future<void> init(String? path) =>
      path != null ? Hive.initFlutter(path) : Hive.initFlutter();

  @override
  bool isAdapterRegistered(int typeId) => Hive.isAdapterRegistered(typeId);

  @override
  void registerAdapter(TypeAdapter<dynamic> adapter) =>
      Hive.registerAdapter(adapter);

  @override
  Future<int> openBox(String name) async {
    final adapter = await HiveAdapterFactory.open<dynamic>(name);
    return adapter.length;
  }
}
