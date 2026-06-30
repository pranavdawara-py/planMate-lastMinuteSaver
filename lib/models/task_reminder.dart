import 'dart:convert';

/// A single reminder attached to a task.
/// Stored as JSON strings inside Task.remindersJson — no separate Hive typeId needed.
class TaskReminder {
  final String id;

  /// When this reminder fires:
  ///   'before_start'    → offsetMinutes before startTime
  ///   'after_start'     → offsetMinutes after startTime (check-in)
  ///   'before_end'      → offsetMinutes before endTime
  ///   'before_deadline' → offsetMinutes before task deadline (task-level only)
  ///   'absolute'        → fires at absoluteTime exactly
  final String triggerMode;

  /// How many minutes before/after the anchor point. Null when triggerMode == 'absolute'.
  final int? offsetMinutes;

  /// Used only when triggerMode == 'absolute'.
  final DateTime? absoluteTime;

  /// Multi-select alert behaviour. Any combination of:
  ///   'silent'      → badge only, no sound, no vibration
  ///   'notification'→ badge + vibration, no sound
  ///   'sound'       → notification with sound (single play)
  ///   'ringtone'    → continuous ringing loop until dismissed (not fullscreen)
  ///   'alarm'       → fullscreen alarm, loops, bypasses Do Not Disturb
  ///   'callout'     → TTS speaks the task name aloud (+ follow-up questions)
  final List<String> alertTypes;

  /// Multiple follow-up questions shown/spoken at reminder time.
  /// Supports {task_name} as a placeholder resolved at fire time.
  final List<String> followUpQuestions;

  /// Log of every time this reminder fired.
  final List<ReminderEvent> history;

  /// Optional path to a user-uploaded custom ringtone file (mp3/aac/ogg/m4a/wav).
  /// null → use the app's default alarm sound.
  /// Only applies when alertTypes contains 'ringtone' or 'alarm'.
  final String? customRingtonePath;

  TaskReminder({
    required this.id,
    required this.triggerMode,
    this.offsetMinutes,
    this.absoluteTime,
    required this.alertTypes,
    List<String>? followUpQuestions,
    // Legacy single-question support (converts to list)
    String? followUpQuestion,
    this.history = const [],
    this.customRingtonePath,
  }) : followUpQuestions = followUpQuestions ??
            (followUpQuestion != null && followUpQuestion.isNotEmpty
                ? [followUpQuestion]
                : const []);

  /// Convenience getter: first follow-up question (or null if none).
  String? get followUpQuestion =>
      followUpQuestions.isNotEmpty ? followUpQuestions.first : null;

  /// Human-readable label for the trigger, e.g. "30 min before start"
  String triggerLabel() {
    if (triggerMode == 'absolute' && absoluteTime != null) {
      final h = absoluteTime!.hour.toString().padLeft(2, '0');
      final m = absoluteTime!.minute.toString().padLeft(2, '0');
      return 'At $h:$m';
    }
    final mins = offsetMinutes ?? 0;
    final timeStr = _formatOffset(mins);
    switch (triggerMode) {
      case 'before_start':
        return '$timeStr before start';
      case 'after_start':
        return '$timeStr after start';
      case 'before_end':
        return '$timeStr before end';
      case 'before_deadline':
        return '$timeStr before deadline';
      default:
        return timeStr;
    }
  }

  String _formatOffset(int mins) {
    if (mins < 60) return '$mins min';
    if (mins % 60 == 0) return '${mins ~/ 60} hr';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'triggerMode': triggerMode,
        'offsetMinutes': offsetMinutes,
        'absoluteTime': absoluteTime?.toIso8601String(),
        'alertTypes': alertTypes,
        'followUpQuestions': followUpQuestions,
        // Legacy field for older readers
        'followUpQuestion':
            followUpQuestions.isNotEmpty ? followUpQuestions.first : null,
        'history': history.map((e) => e.toJson()).toList(),
        'customRingtonePath': customRingtonePath,
      };

  factory TaskReminder.fromJson(Map<String, dynamic> json) {
    // Support both new list format and legacy single-string format
    List<String> parsedQuestions;
    if (json['followUpQuestions'] is List) {
      parsedQuestions = List<String>.from(
          (json['followUpQuestions'] as List).whereType<String>());
    } else if (json['followUpQuestion'] is String &&
        (json['followUpQuestion'] as String).isNotEmpty) {
      parsedQuestions = [json['followUpQuestion'] as String];
    } else {
      parsedQuestions = const [];
    }

    return TaskReminder(
      id: json['id']?.toString() ??
          'rem_${DateTime.now().millisecondsSinceEpoch}_${json.hashCode}',
      triggerMode: json['triggerMode']?.toString() ?? 'before_start',
      offsetMinutes: (json['offsetMinutes'] as num?)?.toInt(),
      absoluteTime: json['absoluteTime'] != null
          ? DateTime.tryParse(json['absoluteTime'] as String)
          : null,
      alertTypes: json['alertTypes'] is List
          ? List<String>.from(json['alertTypes'] as List)
          : ['notification'],
      followUpQuestions: parsedQuestions,
      history: (json['history'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => ReminderEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      customRingtonePath: json['customRingtonePath'] as String?,
    );
  }

  /// Serialize to JSON string for Hive storage.
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from a Hive-stored JSON string.
  static TaskReminder fromJsonString(String s) =>
      TaskReminder.fromJson(jsonDecode(s) as Map<String, dynamic>);

  TaskReminder copyWith({
    String? id,
    String? triggerMode,
    int? offsetMinutes,
    DateTime? absoluteTime,
    List<String>? alertTypes,
    List<String>? followUpQuestions,
    List<ReminderEvent>? history,
    String? customRingtonePath,
    bool clearAbsoluteTime = false,
    bool clearOffsetMinutes = false,
    bool clearFollowUpQuestions = false,
    bool clearCustomRingtonePath = false,
  }) =>
      TaskReminder(
        id: id ?? this.id,
        triggerMode: triggerMode ?? this.triggerMode,
        offsetMinutes:
            clearOffsetMinutes ? null : (offsetMinutes ?? this.offsetMinutes),
        absoluteTime:
            clearAbsoluteTime ? null : (absoluteTime ?? this.absoluteTime),
        alertTypes: alertTypes ?? this.alertTypes,
        followUpQuestions: clearFollowUpQuestions
            ? const []
            : (followUpQuestions ?? this.followUpQuestions),
        history: history ?? this.history,
        customRingtonePath: clearCustomRingtonePath
            ? null
            : (customRingtonePath ?? this.customRingtonePath),
      );
}

/// One firing event for a reminder.
class ReminderEvent {
  final String id;
  final DateTime firedAt;

  /// Snapshot of the follow-up question text at time of firing.
  final String? question;

  /// User's answer: 'yes', 'no', or null (dismissed without answering).
  final String? answer;

  ReminderEvent({
    required this.id,
    required this.firedAt,
    this.question,
    this.answer,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'firedAt': firedAt.toIso8601String(),
        'question': question,
        'answer': answer,
      };

  factory ReminderEvent.fromJson(Map<String, dynamic> json) => ReminderEvent(
        id: json['id'] as String,
        firedAt: DateTime.parse(json['firedAt'] as String),
        question: json['question'] as String?,
        answer: json['answer'] as String?,
      );

  ReminderEvent copyWith({String? answer}) => ReminderEvent(
        id: id,
        firedAt: firedAt,
        question: question,
        answer: answer ?? this.answer,
      );
}
