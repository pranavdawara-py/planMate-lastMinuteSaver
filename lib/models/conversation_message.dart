import 'package:hive/hive.dart';

part 'conversation_message.g.dart';

@HiveType(typeId: 4)
class ConversationMessage extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime timestamp;

  @HiveField(2)
  final String role; // user | model

  @HiveField(3)
  final String text;

  @HiveField(4)
  final List<String> actionsExecuted;

  ConversationMessage({
    required this.id,
    required this.timestamp,
    required this.role,
    required this.text,
    this.actionsExecuted = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'role': role,
        'text': text,
        'actions_executed': actionsExecuted,
      };

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      id: json['id'],
      timestamp: DateTime.parse(json['timestamp']),
      role: json['role'] ?? 'user',
      text: json['text'] ?? '',
      actionsExecuted: List<String>.from(json['actions_executed'] ?? []),
    );
  }
}
