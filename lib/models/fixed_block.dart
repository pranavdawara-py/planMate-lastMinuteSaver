import 'package:hive/hive.dart';

part 'fixed_block.g.dart';

@HiveType(typeId: 2)
class FixedBlock extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  String startTime; // HH:MM (24-hour)

  @HiveField(3)
  String endTime; // HH:MM (24-hour)

  @HiveField(4)
  List<String> days; // ["monday", "tuesday", ...]

  @HiveField(5)
  bool allowOverlap;

  @HiveField(6)
  String notificationType; // silent | none | sound

  FixedBlock({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.days,
    this.allowOverlap = false,
    this.notificationType = 'silent',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'start_time': startTime,
        'end_time': endTime,
        'days': days,
        'allow_overlap': allowOverlap,
        'notification_type': notificationType,
      };

  factory FixedBlock.fromJson(Map<String, dynamic> json) {
    return FixedBlock(
      id: json['id'],
      title: json['title'],
      startTime: json['start_time'],
      endTime: json['end_time'],
      days: List<String>.from(json['days'] ?? []),
      allowOverlap: json['allow_overlap'] ?? false,
      notificationType: json['notification_type'] ?? 'silent',
    );
  }
}
