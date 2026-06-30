// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ConversationMessageAdapter extends TypeAdapter<ConversationMessage> {
  @override
  final int typeId = 4;

  @override
  ConversationMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ConversationMessage(
      id: fields[0] as String,
      timestamp: fields[1] as DateTime,
      role: fields[2] as String,
      text: fields[3] as String,
      actionsExecuted: (fields[4] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, ConversationMessage obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.timestamp)
      ..writeByte(2)
      ..write(obj.role)
      ..writeByte(3)
      ..write(obj.text)
      ..writeByte(4)
      ..write(obj.actionsExecuted);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
