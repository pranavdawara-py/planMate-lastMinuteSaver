import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../models/task.dart';
import '../models/task_reminder.dart';
import '../services/storage_service.dart';

/// Reminder History Screen — Issue 4 implementation.
///
/// Shows every [ReminderEvent] that has been logged across all tasks,
/// grouped by task. Displayed as a tab/panel inside the existing
/// HistoryScreen via the tab bar in AppShell, or it can be pushed onto
/// the navigator from the Settings screen.
///
/// Each event shows:
///   - The question that was asked
///   - The user's answer (Yes / No / No answer)
///   - The time the reminder fired
class ReminderHistoryScreen extends StatefulWidget {
  const ReminderHistoryScreen({super.key});

  @override
  State<ReminderHistoryScreen> createState() => _ReminderHistoryScreenState();
}

class _ReminderHistoryScreenState extends State<ReminderHistoryScreen> {
  String _filter = 'all'; // 'all' | 'yes' | 'no' | 'unanswered'

  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
      builder: (context, storage, _) {
        // Collect all (task, reminder, event) triples across all tasks
        final entries = <_HistoryEntry>[];
        for (final task in storage.getTasks()) {
          // Session-level reminders
          for (final session in task.sessions) {
            for (final reminder in session.reminders) {
              for (final event in reminder.history) {
                entries.add(_HistoryEntry(
                  task: task,
                  reminder: reminder,
                  event: event,
                ));
              }
            }
          }
          // Task-level reminders
          for (final reminder in task.reminders) {
            for (final event in reminder.history) {
              entries.add(_HistoryEntry(
                task: task,
                reminder: reminder,
                event: event,
              ));
            }
          }
        }

        // Apply filter
        final filtered = entries.where((e) {
          switch (_filter) {
            case 'yes':
              return e.event.answer == 'yes';
            case 'no':
              return e.event.answer == 'no';
            case 'unanswered':
              return e.event.answer == null;
            default:
              return true;
          }
        }).toList();

        // Sort newest first
        filtered.sort((a, b) => b.event.firedAt.compareTo(a.event.firedAt));

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFilterBar(),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) =>
                            _buildEventTile(filtered[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterBar() {
    final filters = [
      ('all', 'All'),
      ('yes', '✅ Yes'),
      ('no', '❌ No'),
      ('unanswered', '— Unanswered'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: AppColors.bgPrimary,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final isSelected = _filter == f.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filter = f.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.accentPrimary
                        : AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.accentPrimary
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    f.$2,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEventTile(_HistoryEntry entry) {
    final answer = entry.event.answer;
    Color answerColor;
    String answerLabel;
    IconData answerIcon;

    if (answer == 'yes') {
      answerColor = AppColors.success;
      answerLabel = 'Yes';
      answerIcon = Icons.check_circle_outline;
    } else if (answer == 'no') {
      answerColor = AppColors.danger;
      answerLabel = 'No';
      answerIcon = Icons.cancel_outlined;
    } else {
      answerColor = AppColors.textMuted;
      answerLabel = 'No answer';
      answerIcon = Icons.remove_circle_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: answerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Answer indicator dot
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: answerColor.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(answerIcon, color: answerColor, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Task title
                Text(
                  entry.task.title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                // Question
                if (entry.event.question?.isNotEmpty == true)
                  Text(
                    entry.event.question!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Answer badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: answerColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        answerLabel,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: answerColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Time
                    Text(
                      _formatTime(entry.event.firedAt),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔔', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text(
            'No reminder history yet',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Answers to follow-up questions appear here.',
            style: GoogleFonts.inter(
                fontSize: 12, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}

class _HistoryEntry {
  final Task task;
  final TaskReminder reminder;
  final ReminderEvent event;
  const _HistoryEntry({
    required this.task,
    required this.reminder,
    required this.event,
  });
}
