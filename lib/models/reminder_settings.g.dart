// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reminder_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReminderSettingsAdapter extends TypeAdapter<ReminderSettings> {
  @override
  final int typeId = 1;

  @override
  ReminderSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReminderSettings(
      type: fields[0] as String,
      times: (fields[1] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, ReminderSettings obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.type)
      ..writeByte(1)
      ..write(obj.times);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
