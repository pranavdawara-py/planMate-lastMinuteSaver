import 'package:hive/hive.dart';

part 'day_label.g.dart';

@HiveType(typeId: 3)
class DayLabel extends HiveObject {
  @HiveField(0)
  final String date; // YYYY-MM-DD

  @HiveField(1)
  String label; // e.g. "Exam Day"

  DayLabel({
    required this.date,
    required this.label,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'label': label,
      };

  factory DayLabel.fromJson(Map<String, dynamic> json) {
    return DayLabel(
      date: json['date'],
      label: json['label'],
    );
  }
}
