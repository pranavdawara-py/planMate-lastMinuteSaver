import 'dart:async';
import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/task.dart';
import '../models/task_reminder.dart';
import '../models/work_session.dart';

/// NotificationService — handles all reminder scheduling for planMate.
///
/// ## Alert type matrix:
///
/// | Type         | Sound | Loop | FullScreen | Vibrate | DND bypass |
/// |--------------|-------|------|------------|---------|------------|
/// | notification | ✗     | ✗    | ✗          | ✓       | ✗          |
/// | sound        | ✓     | ✗    | ✗          | ✓       | ✗          |
/// | ringtone     | ✓     | ✓    | ✗          | ✓       | ✗          |
/// | alarm        | ✓     | ✓    | ✓          | ✓       | ✓          |
/// | callout      | TTS   | ✗    | ✗          | ✓       | ✗          |
///
/// "notification" = vibration-only badge (no sound). Formerly called "silent".
/// "sound" = standard notification with a single sound play.
/// "ringtone" = loops until dismissed (no fullscreen).
/// "alarm" = loops + fullscreen + bypasses DND.
/// "callout" = TTS read-out of task name + follow-up questions.
///
/// All scheduled reminders go through the [alarm] package (uses
/// Android AlarmManager exact alarms — survives app kill). The
/// flutter_local_notifications plugin is used only for immediate
/// show() calls and notification channel management.
class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  FlutterTts? _tts;
  bool _isTtsEnabled = true;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  bool get isTtsEnabled => _isTtsEnabled;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // ── Audio asset paths ─────────────────────────────────────────────────────
  static const _assetAlarm = 'assets/alarm.mp3';
  static const _assetSilence = 'assets/silence.mp3';

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (kIsWeb || !_isAndroid) return;
    try {
      // Init flutter_local_notifications
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await _notif.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: _onNotifTapped,
      );

      final androidPlugin = _notif.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      // Channel: notification/sound (standard importance, can sound)
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'planmate_task_channel',
          'Task Reminders',
          description: 'Reminder notifications for planMate tasks',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      // Channel: vibration-only / notification-type (no sound)
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'planmate_vibrate_channel',
          'Silent Reminders',
          description: 'Vibration-only reminder notifications',
          importance: Importance.high,
          playSound: false,
          enableVibration: true,
        ),
      );

      // Channel: alarm (max importance, full-screen intent)
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'planmate_alarm_channel',
          'Task Alarms',
          description: 'Full alarm alerts for planMate tasks',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      // Init alarm package
      await Alarm.init();

      // Init TTS
      _tts = FlutterTts();
      await _tts?.setLanguage('en-IN');
      await _tts?.setSpeechRate(0.5);
      await _tts?.setVolume(1.0);

      _initialized = true;
      debugPrint('NotificationService: initialized');
    } catch (e) {
      debugPrint('NotificationService.init error: $e');
    }
  }

  void setTtsEnabled(bool enabled) {
    _isTtsEnabled = enabled;
    notifyListeners();
  }

  // ── Schedule all reminders for a task ────────────────────────────────────

  Future<void> scheduleTaskReminders(Task task) async {
    if (!_isAndroid || !_initialized) return;
    await cancelTaskAlerts(task.id);

    final now = DateTime.now();
    int scheduled = 0;

    // Per-session reminders
    for (final (:session, :reminder) in task.allSessionReminders) {
      final fireAt = _resolveSession(session, task, reminder);
      if (fireAt == null || fireAt.isBefore(now)) continue;
      await _scheduleReminder(
        uniqueKey: '${task.id}_${session.id}_${reminder.id}',
        taskTitle: task.title,
        reminder: reminder,
        fireAt: fireAt,
      );
      scheduled++;
    }

    // Task-level reminders (deadline-relative)
    for (final reminder in task.reminders) {
      final fireAt = _resolveTask(task, reminder);
      if (fireAt == null || fireAt.isBefore(now)) continue;
      await _scheduleReminder(
        uniqueKey: '${task.id}_task_${reminder.id}',
        taskTitle: task.title,
        reminder: reminder,
        fireAt: fireAt,
      );
      scheduled++;
    }

    debugPrint(
        'NotificationService: scheduled $scheduled reminder(s) for "${task.title}"');
  }

  /// Legacy entry point — kept for backward compat.
  Future<void> scheduleTaskAlerts(Task task) => scheduleTaskReminders(task);

  Future<void> cancelTaskAlerts(String taskId) async {
    if (!_isAndroid || !_initialized) return;
    try {
      final prefix = taskId.substring(0, taskId.length.clamp(0, 10));
      final alarms = Alarm.getAlarms();
      for (final a in alarms) {
        if (a.notificationTitle.contains(prefix)) {
          await Alarm.stop(a.id);
        }
      }
    } catch (e) {
      debugPrint('NotificationService.cancelTaskAlerts error: $e');
    }
  }

  Future<void> cancelTaskRemindersByTask(Task task) =>
      cancelTaskAlerts(task.id);

  // ── Core scheduling ───────────────────────────────────────────────────────

  Future<void> _scheduleReminder({
    required String uniqueKey,
    required String taskTitle,
    required TaskReminder reminder,
    required DateTime fireAt,
  }) async {
    if (fireAt.isBefore(DateTime.now())) return;

    final id = uniqueKey.hashCode.abs() & 0x7FFFFFFF;
    final body = _buildBody(taskTitle, reminder);
    final types = reminder.alertTypes;

    // Determine behaviour by priority: alarm > ringtone > sound > callout > notification
    final isAlarm    = types.contains('alarm');
    final isRingtone = types.contains('ringtone') && !isAlarm;
    final isSound    = types.contains('sound') && !isRingtone && !isAlarm;
    final isCallout  = types.contains('callout');
    // "notification" = vibrate only (no sound); also the fallback when nothing else matches
    final hasSoundLoop = isAlarm || isRingtone || isSound;
    final vibrate = true; // all types vibrate

    // Choose audio path
    final audioPath =
        _resolveAudioPath(reminder.customRingtonePath, hasSoundLoop);

    // Notification icon
    final icon = isAlarm
        ? '⏰'
        : isRingtone
            ? '🔔'
            : isSound
                ? '🔔'
                : isCallout
                    ? '🗣️'
                    : '📋';

    // TTS callout (fires when app is foreground via a timer)
    if (isCallout) {
      _scheduleTtsViaTimer(taskTitle, reminder.followUpQuestions, fireAt);
    }

    // Schedule via alarm package for reliable delivery when app is killed.
    // For "notification"-only type we still use alarm package but with
    // silence audio and no loop — this gives us reliable delivery + vibration.
    try {
      await Alarm.set(
        alarmSettings: AlarmSettings(
          id: id,
          dateTime: fireAt,
          assetAudioPath: hasSoundLoop ? audioPath : _assetSilence,
          notificationTitle: '$icon $taskTitle',
          notificationBody: body,
          loopAudio: isAlarm || isRingtone, // sound plays once; alarm/ringtone loop
          vibrate: vibrate,
          volume: _resolveVolume(types),
          fadeDuration: isAlarm ? 3.0 : 0.0,
          enableNotificationOnKill: false,
          androidFullScreenIntent: isAlarm,
        ),
      );
      debugPrint(
          'NotificationService: scheduled alarm id=$id at $fireAt (types=$types)');
    } catch (e) {
      debugPrint('NotificationService._scheduleReminder error: $e');
    }
  }

  /// Pick the volume based on alert types (highest type wins).
  double _resolveVolume(List<String> types) {
    if (types.contains('alarm'))    return 1.0;
    if (types.contains('ringtone')) return 0.85;
    if (types.contains('sound'))    return 0.65;
    if (types.contains('callout'))  return 0.5;
    return 0.0; // notification-only — no audio volume (silence.mp3)
  }

  /// Resolve the audio file to play.
  /// Prefers user-supplied custom path; falls back to app assets.
  String _resolveAudioPath(String? customPath, bool isLoud) {
    if (customPath != null && customPath.isNotEmpty) {
      try {
        if (File(customPath).existsSync()) return customPath;
      } catch (_) {}
      debugPrint(
          'NotificationService: custom ringtone not found at $customPath, using default');
    }
    return isLoud ? _assetAlarm : _assetSilence;
  }

  // ── Fire time resolution ──────────────────────────────────────────────────

  DateTime? _resolveSession(
      WorkSession session, Task task, TaskReminder reminder) {
    final offset = Duration(minutes: reminder.offsetMinutes ?? 0);
    switch (reminder.triggerMode) {
      case 'absolute':
        return reminder.absoluteTime;
      case 'before_start':
        return session.startTime?.subtract(offset);
      case 'after_start':
        return session.startTime?.add(offset);
      case 'before_end':
        return session.endTime?.subtract(offset);
      default:
        return null;
    }
  }

  DateTime? _resolveTask(Task task, TaskReminder reminder) {
    final offset = Duration(minutes: reminder.offsetMinutes ?? 0);
    switch (reminder.triggerMode) {
      case 'absolute':
        return reminder.absoluteTime;
      case 'before_deadline':
        return task.deadline?.subtract(offset);
      case 'before_start':
        final anchor =
            task.nextUpcomingSession?.startTime ?? task.firstSessionStart;
        return anchor?.subtract(offset);
      default:
        return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _buildBody(String taskTitle, TaskReminder reminder) {
    final label = reminder.triggerLabel();
    final questions = reminder.followUpQuestions
        .map((q) => q.replaceAll('{task_name}', taskTitle))
        .toList();
    if (questions.isNotEmpty) {
      return '$label — ${questions.join(' · ')}';
    }
    return label;
  }

  /// Schedules TTS to fire at [fireAt] — works when app is in foreground.
  void _scheduleTtsViaTimer(
      String taskTitle, List<String> questions, DateTime fireAt) {
    final delay = fireAt.difference(DateTime.now());
    if (delay.isNegative) return;
    Future.delayed(delay, () async {
      if (!_isTtsEnabled || _tts == null) return;
      if (questions.isEmpty) {
        await _tts!.speak('planMate reminder: $taskTitle');
      } else {
        for (var i = 0; i < questions.length; i++) {
          final speech = questions[i].replaceAll('{task_name}', taskTitle);
          await _tts!.speak(speech);
          if (i < questions.length - 1) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
    });
  }

  void _onNotifTapped(NotificationResponse details) {
    debugPrint(
        'NotificationService: notification tapped — ${details.payload}');
  }

  /// Show an immediate notification (for testing or instant alerts).
  Future<void> showImmediate({
    required String title,
    required String body,
    bool silent = false,
  }) async {
    if (!_isAndroid || !_initialized) return;
    await _notif.show(
      DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          silent ? 'planmate_vibrate_channel' : 'planmate_task_channel',
          silent ? 'Silent Reminders' : 'Task Reminders',
          playSound: !silent,
          enableVibration: true,
          priority: Priority.high,
          importance: Importance.high,
        ),
      ),
    );
  }
}
