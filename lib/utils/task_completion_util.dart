import 'package:planmate/models/task.dart';
import 'package:planmate/services/storage_service.dart';
import 'package:planmate/services/notification_service.dart';
import 'package:planmate/utils/recurrence_util.dart';

class TaskCompletionUtil {
  /// Returns true if a next recurring occurrence was generated.
  static Future<bool> toggleComplete(
    Task task,
    StorageService storage,
    NotificationService notif,
  ) async {
    final isDone = task.status == 'complete';
    task.status = isDone ? 'incomplete' : 'complete';
    task.completedAt = task.status == 'complete' ? DateTime.now() : null;

    bool createdNext = false;
    if (task.status == 'complete') {
      final nextTask = RecurrenceUtil.generateNextOccurrence(task);
      if (nextTask != null) {
        await storage.saveTask(nextTask);
        await notif.scheduleTaskReminders(nextTask);
        createdNext = true;
      }
    }

    await storage.saveTask(task);
    if (task.status == 'complete') {
      await notif.cancelTaskAlerts(task.id);
    } else {
      await notif.scheduleTaskReminders(task);
    }
    return createdNext;
  }
}
