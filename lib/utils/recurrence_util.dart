import '../models/task.dart';
import '../models/work_session.dart';

class RecurrenceUtil {
  /// Resolves whether a recurring task should appear on [targetDate].
  static bool isTaskScheduledOnDay(Task task, DateTime targetDate) {
    final taskDate = task.firstSessionStart ?? task.deadline;
    if (taskDate == null) return false;

    // Direct comparison for non-recurring tasks
    if (task.recurrence == 'none') {
      return taskDate.year == targetDate.year &&
          taskDate.month == targetDate.month &&
          taskDate.day == targetDate.day;
    }

    // Do not show recurring instances prior to the initial activation date
    final targetMidnight =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    final taskMidnight =
        DateTime(taskDate.year, taskDate.month, taskDate.day);
    if (targetMidnight.isBefore(taskMidnight)) return false;

    switch (task.recurrence) {
      case 'daily':
        return true;
      case 'weekly':
        return taskDate.weekday == targetDate.weekday;
      case 'monthly':
        return taskDate.day == targetDate.day;
      default:
        return false;
    }
  }

  /// Generates the next occurrence of a recurring task after completion.
  ///
  /// Returns a new [Task] with sessions shifted by 1 day (daily) or 7 days
  /// (weekly). Returns null if the task has no recurrence or no sessions/deadline
  /// to shift from.
  static Task? generateNextOccurrence(Task completed) {
    if (completed.recurrence == 'none' || completed.recurrence == 'custom') {
      return null;
    }

    final now = DateTime.now();
    final newId = 'task_${now.millisecondsSinceEpoch}';

    DateTime? shiftDate(DateTime? original) {
      if (original == null) return null;
      if (completed.recurrence == 'daily') {
        return original.add(const Duration(days: 1));
      } else if (completed.recurrence == 'weekly') {
        return original.add(const Duration(days: 7));
      } else if (completed.recurrence == 'monthly') {
        final nextMonth = original.month + 1;
        final nextYear = original.year + (nextMonth > 12 ? 1 : 0);
        final adjustedMonth = nextMonth > 12 ? 1 : nextMonth;
        // Clamp day to last day of target month (e.g. Jan 31 → Feb 28, not Mar 3)
        final lastDay = DateTime(nextYear, adjustedMonth + 1, 0).day;
        final clampedDay = original.day > lastDay ? lastDay : original.day;
        return DateTime(nextYear, adjustedMonth, clampedDay,
            original.hour, original.minute);
      }
      return original;
    }

    // Shift all sessions forward
    final newSessions = completed.sessions.map((s) {
      return WorkSession(
        id: 'ses_${now.millisecondsSinceEpoch}_${s.id}',
        startTime: shiftDate(s.startTime),
        durationMinutes: s.durationMinutes,
        remindersJson: s.remindersJson,
      );
    }).toList();

    // Shift deadline forward (if set)
    final newDeadline = shiftDate(completed.deadline);

    final next = Task(
      id: newId,
      title: completed.title,
      type: newSessions.any((s) => s.startTime != null)
          ? 'scheduled'
          : 'flexible',
      deadline: newDeadline,
      description: completed.description,
      category: completed.category,
      subtasks: List<String>.from(completed.subtasks),
      recurrence: completed.recurrence,
      status: 'incomplete',
      snoozeHistory: [],
    )..sessions = newSessions;

    // Copy task-level reminders
    next.reminders = completed.reminders;

    return next;
  }
}
