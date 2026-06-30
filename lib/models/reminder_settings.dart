import 'package:hive/hive.dart';

part 'reminder_settings.g.dart';

@HiveType(typeId: 1)
class ReminderSettings extends HiveObject {
  @HiveField(0)
  final String type; // sound | silent | vibration | tts

  @HiveField(1)
  final List<String> times; // e.g., ["30min_before", "1h_before", "1day_before"]

  ReminderSettings({
    required this.type,
    required this.times,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'times': times,
      };

  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    return ReminderSettings(
      type: json['type'] ?? 'sound',
      times: List<String>.from(json['times'] ?? []),
    );
  }
}
