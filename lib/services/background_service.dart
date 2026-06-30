import 'dart:async';
import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/task.dart';
import 'notification_service.dart';

/// Background service — Android only, skipped silently everywhere else.
///
/// ## What it does every 15 minutes:
/// 1. Opens the Hive task box.
/// 2. Finds all incomplete tasks with sessions or reminders in the next 30 min.
/// 3. Ensures [Alarm] entries are set for them (re-schedules if missing).
/// 4. Updates the foreground service notification with a short status line.
///
/// This is a lightweight watchdog — the primary scheduling happens in
/// [NotificationService.scheduleTaskReminders] when the user saves a task.
/// The background service is a safety net for reminders that survive app restart.
class SystemBackgroundService {
  static final SystemBackgroundService _instance =
      SystemBackgroundService._internal();
  factory SystemBackgroundService() => _instance;
  SystemBackgroundService._internal();

  Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      debugPrint('SystemBackgroundService: skipping — Android only');
      return;
    }
    try {
      final service = FlutterBackgroundService();
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: true,
          isForegroundMode: true,
          notificationChannelId: 'planmate_task_channel',
          initialNotificationTitle: 'planMate',
          initialNotificationContent: 'Watching your schedule…',
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: true,
          onForeground: _onStart,
          onBackground: _onIosBackground,
        ),
      );
    } catch (e) {
      debugPrint('SystemBackgroundService.init error: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init notification service and alarm
  final notif = NotificationService();
  await notif.init();

  await Alarm.init();

  // Init Hive so we can read tasks
  await Hive.initFlutter();
  // Note: adapters may not be registered in this isolate — catch errors
  Box<Task>? taskBox;
  try {
    if (!Hive.isBoxOpen('tasks')) {
      taskBox = await Hive.openBox<Task>('tasks');
    } else {
      taskBox = Hive.box<Task>('tasks');
    }
  } catch (e) {
    debugPrint('Background: Hive open error — $e');
  }

  // Update foreground notification
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'planMate',
      content: 'Schedule watcher active',
    );
  }

  // 15-minute watchdog
  Timer.periodic(const Duration(minutes: 15), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!await service.isForegroundService()) return;
    }

    try {
      if (taskBox == null || !taskBox.isOpen) return;

      final now = DateTime.now();
      final windowEnd = now.add(const Duration(minutes: 30));
      int scheduled = 0;

      for (final task in taskBox.values) {
        if (task.status == 'complete') continue;

        // Check all sessions for upcoming reminders in the 30-min window
        bool taskNeedsRescheduling = false;
        for (final session in task.sessions) {
          if (session.startTime == null) continue;
          for (final reminder in session.reminders) {
            final fireAt = _resolveSessionFireTime(session, task, reminder);
            if (fireAt == null) continue;
            if (fireAt.isAfter(now) && fireAt.isBefore(windowEnd)) {
              // Check if alarm already set
              final id = '${task.id}_${session.id}_${reminder.id}'
                  .hashCode
                  .abs() &
                  0x7FFFFFFF;
              final exists =
                  Alarm.getAlarms().any((a) => a.id == id);
              if (!exists) {
                taskNeedsRescheduling = true;
                break;
              }
            }
          }
          if (taskNeedsRescheduling) break;
        }

        if (taskNeedsRescheduling) {
          await notif.scheduleTaskReminders(task);
          scheduled++;
        }
      }

      debugPrint(
          'Background watchdog: checked ${taskBox.length} tasks, rescheduled $scheduled');

      if (service is AndroidServiceInstance) {
        final pending = Alarm.getAlarms().length;
        service.setForegroundNotificationInfo(
          title: 'planMate',
          content: '$pending reminder${pending == 1 ? "" : "s"} scheduled',
        );
      }
    } catch (e) {
      debugPrint('Background watchdog error: $e');
    }
  });
}

DateTime? _resolveSessionFireTime(
    dynamic session, dynamic task, dynamic reminder) {
  try {
    final offset = Duration(minutes: (reminder.offsetMinutes ?? 0) as int);
    switch (reminder.triggerMode as String) {
      case 'before_start':
        return (session.startTime as DateTime?)?.subtract(offset);
      case 'after_start':
        return (session.startTime as DateTime?)?.add(offset);
      case 'before_end':
        return (session.endTime as DateTime?)?.subtract(offset);
      case 'absolute':
        return reminder.absoluteTime as DateTime?;
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}
