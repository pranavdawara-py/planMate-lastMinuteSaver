import 'package:hive/hive.dart';

part 'sync_queue_item.g.dart';

@HiveType(typeId: 5)
class SyncQueueItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime timestamp;

  @HiveField(2)
  final String operation; // create | update | delete

  @HiveField(3)
  final String collection; // tasks | schedule | settings | conversation

  @HiveField(4)
  final Map<dynamic, dynamic> data;

  SyncQueueItem({
    required this.id,
    required this.timestamp,
    required this.operation,
    required this.collection,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'operation': operation,
        'collection': collection,
        'data': data.cast<String, dynamic>(),
      };

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) {
    return SyncQueueItem(
      id: json['id'],
      timestamp: DateTime.parse(json['timestamp']),
      operation: json['operation'],
      collection: json['collection'],
      data: Map<dynamic, dynamic>.from(json['data'] ?? {}),
    );
  }
}
