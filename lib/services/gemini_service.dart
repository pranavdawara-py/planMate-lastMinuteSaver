import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';
import 'export_service.dart';
import 'notification_service.dart';
import '../models/task.dart';
import '../models/work_session.dart';
import '../models/task_reminder.dart';
import '../models/fixed_block.dart';
import '../models/day_label.dart';
import '../models/conversation_message.dart';
import '../utils/gemini_payload_util.dart';

typedef TabSwitchCallback = void Function(String screenName);
typedef TaskDetailCallback = void Function(String taskId);

class GeminiService extends ChangeNotifier {
  GeminiService(this._storageService, this._notificationService);

  final StorageService _storageService;
  final NotificationService _notificationService;

  bool _isGenerating = false;
  String _currentStreamedResponse = '';

  TabSwitchCallback? onNavigate;
  TaskDetailCallback? onOpenTaskDetail;

  bool get isGenerating => _isGenerating;
  String get currentStreamedResponse => _currentStreamedResponse;

  String? get _proxyUrl {
    final key = kIsWeb ? 'WEB_PROXY_URL' : 'PROXY_URL';
    final url = dotenv.env[key]?.trim();
    if (url == null || url.isEmpty || url.contains('your_')) return null;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  // ── App state sent to backend ─────────────────────────────────────────────

  Map<String, dynamic> _buildAppState() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final allTasks = _storageService.getTasks();

    // Compress: full detail for incomplete, compact for today's completed, omit older completed
    final compressedTasks = allTasks.where((t) {
      if (t.status != 'complete') return true;
      if (t.completedAt == null) return false;
      final completedDay =
          DateTime(t.completedAt!.year, t.completedAt!.month, t.completedAt!.day);
      return completedDay == today;
    }).map((t) {
      if (t.status == 'complete') {
        return <String, dynamic>{
          'id': t.id,
          'title': t.title,
          'status': 'complete',
          'completedAt': t.completedAt?.toIso8601String(),
        };
      }
      return t.toJson();
    }).toList();

    return {
      'current_datetime': now.toIso8601String(),
      'tasks': compressedTasks,
      'fixed_blocks':
          _storageService.getFixedBlocks().map((b) => b.toJson()).toList(),
      'day_labels':
          _storageService.getDayLabels().map((l) => l.toJson()).toList(),
      'user_preferences': {
        'default_notification': 'sound',
        'silent_during_fixed_blocks': true,
      },
    };
  }

  List<Map<String, String>> _buildProxyMessages(
      List<ConversationMessage> history) {
    return history
        .map((m) => {
              'role': m.role == 'user' ? 'user' : 'model',
              'content': GeminiPayloadUtil.historyTextForApi(m),
            })
        .toList();
  }

  // ── Streaming simulation ──────────────────────────────────────────────────

  Future<void> _simulateStream(String text) async {
    _currentStreamedResponse = '';
    final chunkSize = text.length > 80 ? 8 : 2;
    for (var i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, text.length);
      _currentStreamedResponse = text.substring(0, end);
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 16));
    }
    _currentStreamedResponse = text;
    notifyListeners();
  }

  // ── Main query ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> sendUserQuery(String userQuery) async {
    _isGenerating = true;
    _currentStreamedResponse = '';
    notifyListeners();

    final userMsg = ConversationMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}_user',
      timestamp: DateTime.now(),
      role: 'user',
      text: userQuery,
    );
    await _storageService.saveChatMessage(userMsg);

    final proxyUrl = _proxyUrl;
    if (proxyUrl == null) {
      await Future.delayed(const Duration(milliseconds: 600));
      final simulated = {
        'message':
            "I'm currently offline — you can still use all app features manually! I'll be back when you reconnect.",
        'requires_confirmation': false,
        'actions': <dynamic>[],
      };
      await _persistAndProcessResponse(simulated);
      _isGenerating = false;
      notifyListeners();
      return simulated;
    }

    try {
      final fullHistory = _storageService.getChatHistory();
      final last20 = fullHistory.length > 20
          ? fullHistory.sublist(fullHistory.length - 20)
          : fullHistory;

      final response = await http
          .post(
            Uri.parse('$proxyUrl/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'messages': _buildProxyMessages(last20),
              'appState': _buildAppState(),
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        throw Exception('Proxy error: ${response.statusCode}');
      }

      final parsedJson = jsonDecode(response.body) as Map<String, dynamic>;
      final messageText = parsedJson['message']?.toString() ?? '';
      await _simulateStream(messageText);
      final messageId = await _persistAndProcessResponse(parsedJson);
      parsedJson['_message_id'] = messageId;

      _isGenerating = false;
      notifyListeners();
      return parsedJson;
    } catch (e) {
      debugPrint('GeminiService: query failed — $e');
      final isTimeout = e.toString().contains('TimeoutException') ||
          e.toString().contains('timeout');
      final isNetworkError = e.toString().contains('SocketException') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network');
      final message = isTimeout || isNetworkError
          ? 'Connection lost. Check your internet and try again.'
          : 'AI service temporarily unavailable. Please try again.';
      final fallback = {
        'message': message,
        'requires_confirmation': false,
        'actions': <dynamic>[],
      };
      await _persistAndProcessResponse(fallback);
      _isGenerating = false;
      notifyListeners();
      return fallback;
    }
  }

  // ── Persist & process response ────────────────────────────────────────────

  Future<String> _persistAndProcessResponse(
      Map<String, dynamic> payload) async {
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_model';
    final actions = GeminiPayloadUtil.normalizeActions(
        List<dynamic>.from(payload['actions'] ?? []));

    final storedPayload = Map<String, dynamic>.from(payload)
      ..['actions'] = actions;

    final needsConfirm = GeminiPayloadUtil.needsConfirmation(storedPayload);
    final statusTag = needsConfirm ? <String>[] : <String>['auto_executed'];

    final modelMsg = ConversationMessage(
      id: messageId,
      timestamp: DateTime.now(),
      role: 'model',
      text: json.encode(storedPayload),
      actionsExecuted: statusTag,
    );
    await _storageService.saveChatMessage(modelMsg);

    if (!needsConfirm && actions.isNotEmpty) {
      await executeParsedActions(actions);
    }

    return messageId;
  }

  // ── Execute actions ───────────────────────────────────────────────────────

  /// Execute a list of normalized `{function, params}` actions.
  /// Always normalizes the input first (idempotent).
  /// Calls [notifyListeners] after ALL actions complete so UI can react.
  Future<void> executeParsedActions(List<dynamic> actions) async {
    if (actions.isEmpty) return;
    final normalized = GeminiPayloadUtil.normalizeActions(actions);

    for (final action in normalized) {
      if (action is! Map) continue;
      final functionName = action['function'] as String?;
      final params = (action['params'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      if (functionName == null) continue;

      try {
        await _executeFunction(functionName, params);
      } catch (e, stack) {
        debugPrint('GeminiService: Error executing "$functionName" — $e\n$stack');
        // Don't rethrow — continue with remaining actions
      }
    }

    // Notify listeners so any UI watching GeminiService knows actions were done.
    // StorageService already notifyListeners() per saveTask() call, but this
    // gives widgets watching GeminiService a chance to react too.
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Task? _findTask(String? taskId) {
    if (taskId == null) return null;
    for (final t in _storageService.getTasks()) {
      if (t.id == taskId) return t;
    }
    return null;
  }

  FixedBlock? _findBlock(String? blockId) {
    if (blockId == null) return null;
    for (final b in _storageService.getFixedBlocks()) {
      if (b.id == blockId) return b;
    }
    return null;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  /// Defensively coerce a raw sessions list from Gemini into WorkSession JSON strings.
  List<String> _parseSessionsJson(List<dynamic> rawSessions) {
    return rawSessions.whereType<Map>().map((s) {
      final sMap = Map<String, dynamic>.from(s);
      final start = _parseDate(sMap['start'] ?? sMap['startTime']);
      final endRaw = _parseDate(sMap['end'] ?? sMap['endTime']);
      // Coerce duration_minutes to int (Gemini sometimes sends as string)
      int? durMins = switch (sMap['duration_minutes']) {
        int v => v,
        String v => int.tryParse(v),
        num v => v.toInt(),
        _ => null,
      };
      durMins ??= (endRaw != null && start != null)
          ? endRaw.difference(start).inMinutes
          : null;

      // Parse per-session reminders
      final rawRem = sMap['reminders'];
      final remindersJson = <String>[];
      if (rawRem is List) {
        for (final r in rawRem.whereType<Map>()) {
          try {
            remindersJson.add(TaskReminder(
              id: r['id']?.toString() ??
                  'rem_${DateTime.now().millisecondsSinceEpoch}',
              triggerMode: r['triggerMode']?.toString() ?? 'before_start',
              offsetMinutes: switch (r['offsetMinutes']) {
                int v => v,
                String v => int.tryParse(v),
                num v => v.toInt(),
                _ => 15,
              },
              alertTypes: r['alertTypes'] is List
                  ? List<String>.from(r['alertTypes'] as List)
                  : ['notification'],
              followUpQuestions: r['followUpQuestions'] is List
                  ? List<String>.from(r['followUpQuestions'] as List)
                  : (r['followUpQuestion']?.toString().isNotEmpty == true
                      ? [r['followUpQuestion'].toString()]
                      : const []),
            ).toJsonString());
          } catch (e) {
            debugPrint('GeminiService: failed to parse reminder — $e');
          }
        }
      }

      return WorkSession(
        id: 'ses_${DateTime.now().millisecondsSinceEpoch}_${s.hashCode}',
        startTime: start,
        durationMinutes: durMins,
        remindersJson: remindersJson,
      ).toJsonString();
    }).toList();
  }

  // ── Function dispatcher ───────────────────────────────────────────────────

  Future<void> _executeFunction(
      String fn, Map<String, dynamic> params) async {
    final now = DateTime.now();

    switch (fn) {
      // ── create_task ──────────────────────────────────────────────────────
      case 'create_task':
        final taskJson = Map<String, dynamic>.from(params);
        taskJson['id'] = 'task_${now.millisecondsSinceEpoch}';
        taskJson['status'] = 'incomplete';

        // Defensive coercion so Task.fromJson never throws on bad AI output
        taskJson['title'] =
            taskJson['title']?.toString().trim().isNotEmpty == true
                ? taskJson['title'].toString()
                : 'New Task';
        taskJson['category'] = taskJson['category']?.toString();
        taskJson['recurrence'] = taskJson['recurrence']?.toString() ?? 'none';
        taskJson['description'] = taskJson['description']?.toString();

        // Parse sessions
        if (taskJson['sessions'] is List) {
          final rawSessions = List<dynamic>.from(taskJson['sessions'] as List);
          // Replace the raw list with WorkSession JSON strings for Task.fromJson
          // Task.fromJson expects List<Map> — keep as List<Map>, not JSON strings
          // (WorkSession.fromJson is called inside Task.fromJson)
          // So we leave sessions as-is here; Task.fromJson handles the conversion.
          // But we do coerce duration_minutes to int:
          taskJson['sessions'] = rawSessions.map((s) {
            if (s is Map) {
              final sm = Map<String, dynamic>.from(s);
              sm['duration_minutes'] = switch (sm['duration_minutes']) {
                int v => v,
                String v => int.tryParse(v),
                num v => v.toInt(),
                _ => null,
              };
              // Coerce reminder offsetMinutes
              if (sm['reminders'] is List) {
                sm['reminders'] = (sm['reminders'] as List).map((r) {
                  if (r is Map) {
                    final rm = Map<String, dynamic>.from(r);
                    rm['offsetMinutes'] = switch (rm['offsetMinutes']) {
                      int v => v,
                      String v => int.tryParse(v),
                      num v => v.toInt(),
                      _ => 15,
                    };
                    // Ensure alertTypes defaults to notification
                    if (rm['alertTypes'] == null) {
                      rm['alertTypes'] = ['notification'];
                    }
                    return rm;
                  }
                  return r;
                }).toList();
              }
              return sm;
            }
            return s;
          }).toList();
        }

        final task = Task.fromJson(taskJson);
        await _storageService.saveTask(task);
        await _notificationService.scheduleTaskReminders(task);
        debugPrint('GeminiService: created task "${task.title}" (${task.id})');
        break;

      // ── edit_task ────────────────────────────────────────────────────────
      case 'edit_task':
        final existing = _findTask(params['task_id']?.toString());
        if (existing == null) {
          debugPrint('GeminiService: edit_task — task not found: ${params['task_id']}');
          break;
        }
        final updates = (params['fields_to_update'] as Map?)
                ?.cast<String, dynamic>() ??
            <String, dynamic>{};

        if (updates.containsKey('title')) {
          existing.title = updates['title'].toString();
        }
        if (updates.containsKey('type')) {
          existing.type = updates['type'].toString();
        }
        if (updates.containsKey('category')) {
          existing.category = updates['category']?.toString();
        }
        if (updates.containsKey('description')) {
          existing.description = updates['description']?.toString();
        }
        if (updates.containsKey('recurrence')) {
          existing.recurrence = updates['recurrence']?.toString() ?? 'none';
        }
        if (updates.containsKey('deadline')) {
          existing.deadline = _parseDate(updates['deadline']);
        }
        // Legacy: start_time/end_time style
        if (updates.containsKey('start_time')) {
          final start = _parseDate(updates['start_time']);
          if (start != null) {
            final end = _parseDate(updates['end_time']);
            final durMins = end?.difference(start).inMinutes;
            final newSess = WorkSession(
              id: existing.sessions.firstOrNull?.id ??
                  'ses_${now.millisecondsSinceEpoch}',
              startTime: start,
              durationMinutes: durMins,
              remindersJson: existing.sessions.firstOrNull?.remindersJson ?? [],
            );
            existing.sessionsJson = [newSess.toJsonString()];
            existing.type = 'scheduled';
          }
        }
        // New sessions array
        if (updates.containsKey('sessions') && updates['sessions'] is List) {
          existing.sessionsJson = _parseSessionsJson(
              List<dynamic>.from(updates['sessions'] as List));
        }

        await _storageService.saveTask(existing);
        await _notificationService.scheduleTaskReminders(existing);
        break;

      // ── delete_task ──────────────────────────────────────────────────────
      case 'delete_task':
        final taskId = params['task_id']?.toString();
        if (taskId != null) {
          await _storageService.deleteTask(taskId);
          await _notificationService.cancelTaskAlerts(taskId);
        }
        break;

      // ── mark_complete ────────────────────────────────────────────────────
      case 'mark_complete':
        final existing = _findTask(params['task_id']?.toString());
        if (existing == null) break;
        existing.status = 'complete';
        existing.completedAt = _parseDate(params['completed_at']) ?? now;
        await _storageService.saveTask(existing);
        await _notificationService.cancelTaskAlerts(existing.id);
        break;

      // ── reschedule_task ──────────────────────────────────────────────────
      case 'reschedule_task':
        final existing = _findTask(params['task_id']?.toString());
        if (existing == null) break;
        if (params['new_sessions'] != null) {
          existing.sessionsJson = _parseSessionsJson(
              List<dynamic>.from(params['new_sessions'] as List));
        }
        if (params['new_deadline'] != null) {
          existing.deadline = _parseDate(params['new_deadline']);
        }
        await _storageService.saveTask(existing);
        await _notificationService.scheduleTaskReminders(existing);
        break;

      // ── cascade_reschedule ───────────────────────────────────────────────
      case 'cascade_reschedule':
        final fromTaskId = params['from_task_id']?.toString();
        final shiftMinutes = switch (params['shift_minutes']) {
          int v => v,
          String v => int.tryParse(v) ?? 0,
          num v => v.toInt(),
          _ => 0,
        };
        final pivot = _findTask(fromTaskId);
        if (pivot == null || shiftMinutes <= 0) break;
        final pivotStart = pivot.firstSessionStart;
        if (pivotStart == null) break;
        for (final t in _storageService.getTasks()) {
          if (t.id == fromTaskId) continue;
          final tStart = t.firstSessionStart;
          if (tStart != null && tStart.isAfter(pivotStart)) {
            t.sessionsJson = t.sessions.map((s) => WorkSession(
                  id: s.id,
                  startTime: s.startTime?.add(Duration(minutes: shiftMinutes)),
                  durationMinutes: s.durationMinutes,
                  remindersJson: s.remindersJson,
                ).toJsonString()).toList();
            await _storageService.saveTask(t);
          }
        }
        break;

      // ── reschedule_incomplete ────────────────────────────────────────────
      case 'reschedule_incomplete':
        final taskIds = List<String>.from(params['task_ids'] ?? []);
        final newSessions = List<dynamic>.from(params['new_sessions'] ?? []);
        for (var i = 0; i < taskIds.length; i++) {
          final t = _findTask(taskIds[i]);
          if (t == null) continue;
          if (i < newSessions.length) {
            final s = newSessions[i];
            DateTime? startDt;
            int? durMins;
            if (s is String) {
              startDt = _parseDate(s);
            } else if (s is Map) {
              startDt = _parseDate(s['start']);
              durMins = switch (s['duration_minutes']) {
                int v => v,
                String v => int.tryParse(v),
                num v => v.toInt(),
                _ => null,
              };
              if (durMins == null) {
                final end = _parseDate(s['end']);
                durMins = (end != null && startDt != null)
                    ? end.difference(startDt).inMinutes
                    : null;
              }
            }
            if (startDt != null) {
              t.sessionsJson = [
                WorkSession(
                  id: 'ses_${now.millisecondsSinceEpoch}_$i',
                  startTime: startDt,
                  durationMinutes: durMins,
                ).toJsonString()
              ];
              await _storageService.saveTask(t);
            }
          }
        }
        break;

      // ── create_fixed_block ───────────────────────────────────────────────
      case 'create_fixed_block':
        final block = FixedBlock(
          id: 'block_${now.millisecondsSinceEpoch}',
          title: params['title']?.toString() ?? 'Fixed Block',
          startTime: params['start_time']?.toString() ?? '09:00',
          endTime: params['end_time']?.toString() ?? '10:00',
          days: List<String>.from(params['days'] ?? []),
          allowOverlap: params['allow_overlap'] == true,
          notificationType: params['notification_type']?.toString() ?? 'sound',
        );
        await _storageService.saveFixedBlock(block);
        break;

      // ── edit_fixed_block ─────────────────────────────────────────────────
      case 'edit_fixed_block':
        final existing = _findBlock(params['block_id']?.toString());
        if (existing == null) break;
        final updates = (params['fields_to_update'] as Map?)
                ?.cast<String, dynamic>() ??
            {};
        if (updates.containsKey('title')) existing.title = updates['title'].toString();
        if (updates.containsKey('start_time')) existing.startTime = updates['start_time'].toString();
        if (updates.containsKey('end_time')) existing.endTime = updates['end_time'].toString();
        await _storageService.saveFixedBlock(existing);
        break;

      // ── delete_fixed_block ───────────────────────────────────────────────
      case 'delete_fixed_block':
        final blockId = params['block_id']?.toString();
        if (blockId != null) await _storageService.deleteFixedBlock(blockId);
        break;

      // ── create_day_label ─────────────────────────────────────────────────
      case 'create_day_label':
        final date = params['date']?.toString();
        final label = params['label']?.toString();
        if (date != null && label != null) {
          await _storageService.saveDayLabel(DayLabel(date: date, label: label));
        }
        break;

      // ── generate_day_plan ────────────────────────────────────────────────
      case 'generate_day_plan':
        final plan = List<dynamic>.from(params['plan'] ?? []);
        for (final item in plan) {
          if (item is! Map) continue;
          final t = _findTask(item['task_id']?.toString());
          if (t == null) continue;
          final start = _parseDate(item['scheduled_start']);
          final end = _parseDate(item['scheduled_end']);
          if (start != null) {
            final durMins = end?.difference(start).inMinutes;
            final newSession = WorkSession(
              id: 'ses_${now.millisecondsSinceEpoch}_${t.id.hashCode}',
              startTime: start,
              durationMinutes: durMins,
            );
            if (t.sessionsJson.isEmpty) {
              t.sessionsJson = [newSession.toJsonString()];
            } else {
              t.sessionsJson[0] = newSession.toJsonString();
            }
            await _storageService.saveTask(t);
          }
        }
        break;

      // ── export_schedule ──────────────────────────────────────────────────
      case 'export_schedule':
        final range = params['date_range']?.toString() ?? 'today';
        DateTime exportDay = DateTime(now.year, now.month, now.day);
        if (range == 'custom' && params['from'] != null) {
          exportDay = DateTime.tryParse(params['from'].toString()) ?? exportDay;
        }
        final tasks = _storageService.getTasks().where((t) {
          final d = t.firstSessionStart ?? t.deadline;
          if (d == null) return false;
          return d.year == exportDay.year &&
              d.month == exportDay.month &&
              d.day == exportDay.day;
        }).toList();
        await ExportService().exportDaySchedule(exportDay, tasks);
        break;

      // ── open_screen ──────────────────────────────────────────────────────
      case 'open_screen':
        final screen = params['screen']?.toString();
        if (screen != null && onNavigate != null) {
          // Use post-frame to avoid calling during build
          WidgetsBinding.instance.addPostFrameCallback((_) => onNavigate!(screen));
        }
        break;

      // ── open_task_detail ─────────────────────────────────────────────────
      case 'open_task_detail':
        final taskId = params['task_id']?.toString();
        if (taskId != null && onOpenTaskDetail != null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => onOpenTaskDetail!(taskId));
        }
        break;

      // ── update_settings ──────────────────────────────────────────────────
      case 'update_settings':
        final settingKey = params['setting_key']?.toString();
        final settingValue = params['setting_value'];
        debugPrint('GeminiService: update_settings — $settingKey = $settingValue');
        if (settingKey == 'tts_enabled' && !kIsWeb) {
          _notificationService.setTtsEnabled(settingValue == true);
        }
        break;

      default:
        debugPrint('GeminiService: unknown function "$fn"');
    }
  }
}
