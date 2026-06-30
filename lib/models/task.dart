import 'package:hive/hive.dart';
import 'work_session.dart';
import 'task_reminder.dart';

part 'task.g.dart';

@HiveType(typeId: 0)
class Task extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String title;

  /// Auto-derived from sessions: 'scheduled' if sessions exist, else 'flexible'.
  /// Stored so the AI / Gemini can refer to it without re-computing.
  @HiveField(2)
  String type;

  /// DEPRECATED: kept only for Hive schema compatibility with old data.
  /// Going forward, use [sessions] instead.
  @HiveField(3)
  DateTime? startTime;

  /// DEPRECATED: kept only for Hive schema compatibility with old data.
  @HiveField(4)
  DateTime? endTime;

  /// Hard deadline — no matter how many sessions, task must be done by this.
  @HiveField(5)
  DateTime? deadline;

  @HiveField(6)
  String? description;

  @HiveField(7)
  String? category; // Work | Personal | College | Health | Other

  @HiveField(8)
  List<String> subtasks;

  /// JSON-encoded `List<TaskReminder>`.
  /// Replaces old ReminderSettings (HiveField(9)).
  @HiveField(9)
  List<String> remindersJson;

  @HiveField(10)
  String recurrence; // none | daily | weekly | custom

  @HiveField(11)
  String status; // incomplete | complete

  @HiveField(12)
  List<DateTime> snoozeHistory;

  @HiveField(13)
  DateTime? completedAt;

  /// JSON-encoded `List<WorkSession>`.
  /// Each entry is one planned timetable block for this task.
  /// All sessions entered at creation time. Multiple sessions work toward [deadline].
  @HiveField(14)
  List<String> sessionsJson;

  Task({
    required this.id,
    required this.title,
    this.type = 'flexible',
    this.startTime,
    this.endTime,
    this.deadline,
    this.description,
    this.category,
    this.subtasks = const [],
    this.remindersJson = const [],
    this.recurrence = 'none',
    this.status = 'incomplete',
    this.snoozeHistory = const [],
    this.completedAt,
    this.sessionsJson = const [],
  });

  // ---------------------------------------------------------------------------
  // Computed accessors — parse JSON on demand
  // ---------------------------------------------------------------------------

  List<WorkSession> get sessions {
    final list = sessionsJson.map(WorkSession.fromJsonString).toList();
    list.sort((a, b) {
      if (a.startTime == null && b.startTime == null) return 0;
      if (a.startTime == null) return 1; // free sessions to end
      if (b.startTime == null) return -1;
      return a.startTime!.compareTo(b.startTime!);
    });
    return list;
  }

  set sessions(List<WorkSession> value) {
    sessionsJson = value.map((s) => s.toJsonString()).toList();
    // Keep deprecated fields in sync so old code doesn't break
    final timed = value.where((s) => s.startTime != null).toList();
    startTime = timed.isNotEmpty ? timed.first.startTime : null;
    endTime = timed.isNotEmpty ? timed.last.endTime : null;
    type = timed.isNotEmpty ? 'scheduled' : 'flexible';
  }

  /// Sessions that have a fixed start time.
  List<WorkSession> get timedSessions =>
      sessions.where((s) => s.startTime != null).toList();

  /// Sessions with no fixed time (free/flexible sessions).
  List<WorkSession> get freeSessions =>
      sessions.where((s) => s.startTime == null).toList();

  /// All reminders across ALL sessions (flattened). Used for scheduling.
  List<({WorkSession session, TaskReminder reminder})> get allSessionReminders {
    final result = <({WorkSession session, TaskReminder reminder})>[];
    for (final session in sessions) {
      for (final reminder in session.reminders) {
        result.add((session: session, reminder: reminder));
      }
    }
    return result;
  }

  List<TaskReminder> get reminders =>
      remindersJson.map(TaskReminder.fromJsonString).toList();

  set reminders(List<TaskReminder> value) {
    remindersJson = value.map((r) => r.toJsonString()).toList();
  }

  // ---------------------------------------------------------------------------
  // Convenience helpers
  // ---------------------------------------------------------------------------

  /// The very first timed session start time (null if no timed sessions).
  DateTime? get firstSessionStart {
    for (final s in timedSessions) {
      if (s.startTime != null) return s.startTime;
    }
    return null;
  }

  /// The very last timed session end time (null if no timed sessions or last has no duration).
  DateTime? get lastSessionEnd {
    final withEnd = timedSessions.where((s) => s.endTime != null).toList();
    return withEnd.isNotEmpty ? withEnd.last.endTime : null;
  }

  /// Next upcoming timed session.
  WorkSession? get nextUpcomingSession {
    final now = DateTime.now();
    return timedSessions
        .where((s) => s.startTime!.isAfter(now))
        .firstOrNull;
  }

  /// Session currently in progress.
  WorkSession? get activeSession =>
      timedSessions.where((s) => s.isInProgress).firstOrNull;

  bool get isOverdue =>
      status != 'complete' &&
      deadline != null &&
      deadline!.isBefore(DateTime.now());

  bool get isToday {
    final now = DateTime.now();
    // Has a timed session today
    if (timedSessions.any((s) =>
        s.startTime!.year == now.year &&
        s.startTime!.month == now.month &&
        s.startTime!.day == now.day)) { return true; }
    // Or deadline is today
    if (deadline != null &&
        deadline!.year == now.year &&
        deadline!.month == now.month &&
        deadline!.day == now.day) { return true; }
    return false;
  }

  /// Returns timed sessions that fall on [day].
  List<WorkSession> sessionsOnDay(DateTime day) {
    return timedSessions.where((s) =>
        s.startTime!.year == day.year &&
        s.startTime!.month == day.month &&
        s.startTime!.day == day.day).toList();
  }

  // ---------------------------------------------------------------------------
  // Serialization — used by GeminiService
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'deadline': deadline?.toIso8601String(),
        'description': description,
        'category': category,
        'subtasks': subtasks,
        'reminders': reminders.map((r) => r.toJson()).toList(),
        'recurrence': recurrence,
        'status': status,
        'snooze_history': snoozeHistory.map((d) => d.toIso8601String()).toList(),
        'completed_at': completedAt?.toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> json) {
    final t = Task(
      id: json['id'] as String,
      title: json['title'] as String,
      type: json['type']?.toString() ?? 'flexible',
      deadline: json['deadline'] != null
          ? DateTime.tryParse(json['deadline'] as String)
          : null,
      description: json['description'] as String?,
      category: json['category'] as String?,
      subtasks: List<String>.from(json['subtasks'] ?? []),
      recurrence: json['recurrence']?.toString() ?? 'none',
      status: json['status']?.toString() ?? 'incomplete',
      snoozeHistory: (json['snooze_history'] as List?)
              ?.map((d) => DateTime.parse(d as String))
              .toList() ??
          [],
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
    );

    // Parse sessions (new format with per-session reminders)
    if (json['sessions'] is List) {
      final rawSessions = json['sessions'] as List;
      t.sessions = rawSessions.map((s) {
        if (s is Map) {
          return WorkSession.fromJson(Map<String, dynamic>.from(s));
        }
        return WorkSession(
          id: 'ses_${DateTime.now().millisecondsSinceEpoch}',
        );
      }).toList();
    } else if (json['start_time'] != null) {
      // Legacy fallback: AI sent start_time/end_time style
      final start = DateTime.tryParse(json['start_time'] as String? ?? '');
      final end = json['end_time'] != null
          ? DateTime.tryParse(json['end_time'] as String? ?? '')
          : null;
      if (start != null) {
        int? durationMinutes;
        if (end != null) durationMinutes = end.difference(start).inMinutes;
        t.sessions = [
          WorkSession(
            id: 'session_${DateTime.now().millisecondsSinceEpoch}',
            startTime: start,
            durationMinutes: durationMinutes,
          )
        ];
      }
    }

    // Parse reminders
    if (json['reminders'] is List) {
      t.reminders = (json['reminders'] as List)
          .whereType<Map>()
          .map((r) => TaskReminder.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    }

    return t;
  }
}
