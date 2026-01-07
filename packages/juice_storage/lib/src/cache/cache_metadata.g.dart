// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_metadata.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CacheMetadataAdapter extends TypeAdapter<CacheMetadata> {
  @override
  final int typeId = 200;

  @override
  CacheMetadata read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CacheMetadata(
      storageKey: fields[0] as String,
      expiresAt: fields[1] as DateTime,
      createdAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, CacheMetadata obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.storageKey)
      ..writeByte(1)
      ..write(obj.expiresAt)
      ..writeByte(2)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CacheMetadataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
