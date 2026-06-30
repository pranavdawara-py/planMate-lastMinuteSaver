import 'dart:convert';

import '../models/conversation_message.dart';

/// Parses and normalizes Gemini proxy response payloads.
class GeminiPayloadUtil {
  static Map<String, dynamic>? parsePayload(String raw) {
    try {
      return json.decode(raw.trim()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String displayText(ConversationMessage msg) {
    if (msg.role == 'user') return msg.text;
    final payload = parsePayload(msg.text);
    return payload?['message']?.toString() ?? msg.text;
  }

  static String historyTextForApi(ConversationMessage msg) {
    if (msg.role == 'user') return msg.text;

    final payload = parsePayload(msg.text);
    if (payload == null) return msg.text;

    final message = payload['message']?.toString() ?? msg.text;
    final actions = List<dynamic>.from(payload['actions'] ?? []);

    if (actions.isEmpty) return message;

    // Communicate execution status so AI understands what happened
    final wasConfirmed = msg.actionsExecuted.contains('confirmation_confirmed') ||
        msg.actionsExecuted.contains('auto_executed');
    final wasCancelled = msg.actionsExecuted.contains('confirmation_cancelled');
    final isPending = !wasConfirmed && !wasCancelled;

    // Append compact action summary so AI remembers what it proposed/executed
    final actionSummary = actions.map((a) {
      if (a is! Map) return '';
      final fn = a['function'] ?? a['name'] ?? '?';
      final p = (a['params'] as Map?)?.cast<String, dynamic>() ?? {};
      final keyParams = p.entries
          .where((e) => e.value != null && e.value.toString().isNotEmpty)
          .take(2)
          .map((e) => '${e.key}=${e.value}')
          .join(', ');
      return '$fn($keyParams)';
    }).where((s) => s.isNotEmpty).join('; ');

    if (wasConfirmed) {
      return '$message\n[Actions EXECUTED: $actionSummary]';
    } else if (wasCancelled) {
      return '$message\n[Actions CANCELLED by user: $actionSummary]';
    } else if (isPending) {
      return '$message\n[Actions PENDING user confirmation: $actionSummary]';
    }
    return '$message\n[Actions: $actionSummary]';
  }

  static bool confirmationHandled(ConversationMessage msg) {
    return msg.actionsExecuted.contains('confirmation_confirmed') ||
        msg.actionsExecuted.contains('confirmation_cancelled') ||
        msg.actionsExecuted.contains('auto_executed');
  }

  static bool needsConfirmation(Map<String, dynamic> payload) {
    return payload['requires_confirmation'] == true &&
        (payload['actions'] as List?)?.isNotEmpty == true;
  }

  /// Accepts both `{function, params}` and flat action maps from Gemini.
  static List<Map<String, dynamic>> normalizeActions(List<dynamic> raw) {
    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final fn = map['function'] as String? ?? map['name'] as String?;
      if (fn == null || fn.isEmpty) continue;

      Map<String, dynamic> params;
      if (map['params'] is Map) {
        params = Map<String, dynamic>.from(map['params'] as Map);
      } else if (map['arguments'] is Map) {
        params = Map<String, dynamic>.from(map['arguments'] as Map);
      } else {
        params = Map<String, dynamic>.from(map);
        params.remove('function');
        params.remove('name');
        params.remove('params');
        params.remove('arguments');
      }
      result.add({'function': fn, 'params': params});
    }
    return result;
  }

  static String resolveTaskType(Map<String, dynamic> params) {
    final start = params['start_time'];
    final end = params['end_time'];
    if (start != null && end != null) return 'fixed';
    final explicit = params['type']?.toString();
    if (explicit == 'fixed' || explicit == 'flexible') return explicit!;
    return 'flexible';
  }
}
