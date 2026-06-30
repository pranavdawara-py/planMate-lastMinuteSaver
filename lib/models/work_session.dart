import 'dart:convert';
import 'task_reminder.dart';

/// A single planned work session for a task.
///
/// A task can have:
/// - ZERO sessions  → flexible task (no time assigned, user does it whenever free)
/// - ONE session    → single block (e.g. "Study 2–4 PM")
/// - MANY sessions  → multi-part task (e.g. "Part 1: 2–4 PM, Part 2: 8–9 PM tomorrow")
///
/// ## Key design (per developer intent):
/// - [startTime] is OPTIONAL. Null = free/flexible session (user hasn't given it a time slot yet).
/// - [durationMinutes] is OPTIONAL. Null = open-ended / unknown duration.
/// - Together they define a time block. Both can be null (free-floating session).
/// - [endTime] is a COMPUTED getter: startTime + durationMinutes (if both set).
/// - Each session carries its OWN [reminders] list — reminders are per-session, not per-task.
///
/// ## Reminder options per session:
/// - Callout (TTS speaks task name)
/// - Follow-up question(s) with yes/no logging
/// - Ringtone / Alarm (ringtone-style or full alarm)
/// - Any combination of the above
///
/// Stored as JSON strings in Task.sessionsJson for Hive compatibility.
class WorkSession {
  final String id;

  /// When this work block starts. NULL = free/flexible session (no fixed time).
  final DateTime? startTime;

  /// How long this session is expected to run, in minutes.
  /// NULL = open-ended (user will stop when done).
  final int? durationMinutes;

  /// Reminders that belong specifically to THIS session.
  /// Each reminder fires relative to this session's start/end.
  /// Stored as JSON strings for compactness.
  final List<String> remindersJson;

  WorkSession({
    required this.id,
    this.startTime,
    this.durationMinutes,
    List<String>? remindersJson,
  }) : remindersJson = remindersJson ?? const [];

  // ── Computed helpers ──────────────────────────────────────────────────────

  /// Computed end time = startTime + durationMinutes (null if either is null).
  DateTime? get endTime {
    if (startTime == null || durationMinutes == null) return null;
    return startTime!.add(Duration(minutes: durationMinutes!));
  }

  /// Is this a free/flexible session (no fixed time)?
  bool get isFree => startTime == null;

  /// Is this session currently in progress?
  bool get isInProgress {
    if (startTime == null) return false;
    final now = DateTime.now();
    if (startTime!.isAfter(now)) return false;
    final end = endTime;
    return end == null || end.isAfter(now);
  }

  /// Is this session upcoming (hasn't started yet)?
  bool get isUpcoming => startTime != null && startTime!.isAfter(DateTime.now());

  /// Has this session fully ended?
  bool get isPast {
    final end = endTime;
    if (end != null) return end.isBefore(DateTime.now());
    if (startTime != null) return startTime!.isBefore(DateTime.now());
    return false;
  }

  /// Parse reminders from their stored JSON strings.
  List<TaskReminder> get reminders =>
      remindersJson.map(TaskReminder.fromJsonString).toList();

  /// Human-readable label for the session block.
  /// e.g. "2:00 PM – 4:00 PM" or "2:00 PM · 90 min" or "Free session"
  String get label {
    if (startTime == null) return 'Free session';
    final s = _fmt(startTime!);
    if (endTime != null) return '$s – ${_fmt(endTime!)}';
    if (durationMinutes != null) return '$s · ${_fmtDuration(durationMinutes!)}';
    return '$s onwards';
  }

  String _fmt(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $period';
  }

  String _fmtDuration(int mins) {
    if (mins < 60) return '$mins min';
    if (mins % 60 == 0) return '${mins ~/ 60} hr';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  // ── Serialization ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': startTime?.toIso8601String(),
        'duration_minutes': durationMinutes,
        'reminders_json': remindersJson,
        // Write computed end for any legacy readers
        'end': endTime?.toIso8601String(),
      };

  factory WorkSession.fromJson(Map<String, dynamic> json) {
    // Parse startTime — support both new 'start' key and legacy 'startTime'
    final startRaw = (json['start'] ?? json['startTime']) as String?;
    final startTime = startRaw != null ? DateTime.tryParse(startRaw) : null;

    // Parse durationMinutes — prefer new field, fall back to computing from end
    int? durationMinutes = (json['duration_minutes'] as num?)?.toInt();
    if (durationMinutes == null && startTime != null && json['end'] != null) {
      final end = DateTime.tryParse(json['end'] as String? ?? '');
      if (end != null) {
        durationMinutes = end.difference(startTime).inMinutes;
      }
    }

    // Parse per-session reminders
    final rawReminders = json['reminders_json'];
    final aiReminders = json['reminders'];
    final List<String> remindersJson;
    if (rawReminders is List) {
      remindersJson = rawReminders.cast<String>().toList();
    } else if (aiReminders is List) {
      remindersJson = aiReminders
          .whereType<Map>()
          .map((r) => TaskReminder.fromJson(Map<String, dynamic>.from(r)).toJsonString())
          .toList();
    } else {
      remindersJson = const [];
    }

    return WorkSession(
      id: json['id'] as String? ?? 'ses_${DateTime.now().millisecondsSinceEpoch}',
      startTime: startTime,
      durationMinutes: durationMinutes,
      remindersJson: remindersJson,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static WorkSession fromJsonString(String s) =>
      WorkSession.fromJson(jsonDecode(s) as Map<String, dynamic>);

  WorkSession copyWith({
    DateTime? startTime,
    int? durationMinutes,
    List<TaskReminder>? reminders,
    List<String>? remindersJson,
    bool clearStart = false,
    bool clearDuration = false,
  }) {
    final newRemindersJson = remindersJson ??
        (reminders != null
            ? reminders.map((r) => r.toJsonString()).toList()
            : this.remindersJson);
    return WorkSession(
      id: id,
      startTime: clearStart ? null : (startTime ?? this.startTime),
      durationMinutes:
          clearDuration ? null : (durationMinutes ?? this.durationMinutes),
      remindersJson: newRemindersJson,
    );
  }
}
