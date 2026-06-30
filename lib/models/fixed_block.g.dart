// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fixed_block.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FixedBlockAdapter extends TypeAdapter<FixedBlock> {
  @override
  final int typeId = 2;

  @override
  FixedBlock read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FixedBlock(
      id: fields[0] as String,
      title: fields[1] as String,
      startTime: fields[2] as String,
      endTime: fields[3] as String,
      days: (fields[4] as List).cast<String>(),
      allowOverlap: fields[5] as bool,
      notificationType: fields[6] as String,
    );
  }

  @override
  void write(BinaryWriter writer, FixedBlock obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.startTime)
      ..writeByte(3)
      ..write(obj.endTime)
      ..writeByte(4)
      ..write(obj.days)
      ..writeByte(5)
      ..write(obj.allowOverlap)
      ..writeByte(6)
      ..write(obj.notificationType);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FixedBlockAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
