// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 0;

  @override
  Task read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Task(
      id: fields[0] as String,
      title: fields[1] as String,
      type: fields[2] as String,
      startTime: fields[3] as DateTime?,
      endTime: fields[4] as DateTime?,
      deadline: fields[5] as DateTime?,
      description: fields[6] as String?,
      category: fields[7] as String?,
      subtasks: (fields[8] as List).cast<String>(),
      remindersJson: (fields[9] as List).cast<String>(),
      recurrence: fields[10] as String,
      status: fields[11] as String,
      snoozeHistory: (fields[12] as List).cast<DateTime>(),
      completedAt: fields[13] as DateTime?,
      sessionsJson: (fields[14] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Task obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.startTime)
      ..writeByte(4)
      ..write(obj.endTime)
      ..writeByte(5)
      ..write(obj.deadline)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.category)
      ..writeByte(8)
      ..write(obj.subtasks)
      ..writeByte(9)
      ..write(obj.remindersJson)
      ..writeByte(10)
      ..write(obj.recurrence)
      ..writeByte(11)
      ..write(obj.status)
      ..writeByte(12)
      ..write(obj.snoozeHistory)
      ..writeByte(13)
      ..write(obj.completedAt)
      ..writeByte(14)
      ..write(obj.sessionsJson);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
