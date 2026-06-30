// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'day_label.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DayLabelAdapter extends TypeAdapter<DayLabel> {
  @override
  final int typeId = 3;

  @override
  DayLabel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DayLabel(
      date: fields[0] as String,
      label: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, DayLabel obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.label);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayLabelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
