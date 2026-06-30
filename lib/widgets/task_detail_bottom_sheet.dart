import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_colors.dart';
import '../models/task.dart';
import '../models/work_session.dart';
import '../models/task_reminder.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../utils/recurrence_util.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry points
// ─────────────────────────────────────────────────────────────────────────────

class TaskSheet {
  static Future<void> showCreate(BuildContext context) => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => const _TaskSheetWidget(task: null),
      );

  static Future<void> showEdit(BuildContext context, Task task) =>
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _TaskSheetWidget(task: task),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Draft models
// ─────────────────────────────────────────────────────────────────────────────

class _ReminderDraft {
  String triggerMode;
  int? offsetMinutes;
  DateTime? absoluteTime;
  List<String> alertTypes;
  List<String> followUpQuestions;

  /// Path to user-uploaded custom ringtone (mp3/aac/ogg). null = use default.
  String? customRingtonePath;

  _ReminderDraft({
    this.triggerMode = 'before_start',
    this.offsetMinutes = 15,
    this.absoluteTime,
    required this.alertTypes,
    List<String>? followUpQuestions,
    String? followUpQuestion,
    this.customRingtonePath,
  }) : followUpQuestions = followUpQuestions ??
            (followUpQuestion != null && followUpQuestion.trim().isNotEmpty
                ? [followUpQuestion]
                : []);

  factory _ReminderDraft.fresh() =>
      _ReminderDraft(alertTypes: ['notification'], offsetMinutes: 15);

  factory _ReminderDraft.fromModel(TaskReminder r) => _ReminderDraft(
        triggerMode: r.triggerMode,
        offsetMinutes: r.offsetMinutes,
        absoluteTime: r.absoluteTime,
        alertTypes: List<String>.from(r.alertTypes),
        followUpQuestions: List<String>.from(r.followUpQuestions),
        customRingtonePath: r.customRingtonePath,
      );

  TaskReminder toModel() => TaskReminder(
        id: 'rem_${DateTime.now().millisecondsSinceEpoch}_$hashCode',
        triggerMode: triggerMode,
        offsetMinutes: offsetMinutes,
        absoluteTime: absoluteTime,
        alertTypes: alertTypes,
        followUpQuestions:
            followUpQuestions.where((q) => q.trim().isNotEmpty).toList(),
        customRingtonePath: customRingtonePath,
      );
}

class _SessionDraft {
  DateTime? startTime;
  int? durationMinutes;
  List<_ReminderDraft> reminders;

  _SessionDraft({
    this.startTime,
    this.durationMinutes,
    List<_ReminderDraft>? reminders,
  }) : reminders = reminders ?? [];

  DateTime? get endTime => (startTime != null && durationMinutes != null)
      ? startTime!.add(Duration(minutes: durationMinutes!))
      : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TaskSheetWidget extends StatefulWidget {
  final Task? task;
  const _TaskSheetWidget({this.task});

  @override
  State<_TaskSheetWidget> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheetWidget> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _category;
  DateTime? _deadline;
  String _recurrence = 'none';
  List<_SessionDraft> _sessions = [];
  bool _showMore = false;
  String? _error;
  String _status = 'incomplete';
  DateTime? _completedAt;

  bool get _isCreate => widget.task == null;

  static const _recurrenceOptions = [
    ('none', 'Once', Icons.looks_one_outlined),
    ('daily', 'Daily', Icons.today_outlined),
    ('weekly', 'Weekly', Icons.date_range_outlined),
    ('monthly', 'Monthly', Icons.calendar_month_outlined),
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    if (t != null) {
      _titleCtrl.text = t.title;
      _descCtrl.text = t.description ?? '';
      _category = t.category;
      _deadline = t.deadline;
      _recurrence = t.recurrence;
      _status = t.status;
      _completedAt = t.completedAt;
      _sessions = t.sessions
          .map((s) => _SessionDraft(
                startTime: s.startTime,
                durationMinutes: s.durationMinutes,
                reminders: s.reminders.map(_ReminderDraft.fromModel).toList(),
              ))
          .toList();
      _showMore = _category != null ||
          _deadline != null ||
          _descCtrl.text.isNotEmpty ||
          _recurrence != 'none';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(bottom: bottom),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Handle(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),

                  _TitleField(ctrl: _titleCtrl, error: _error),
                  const SizedBox(height: 20),

                  // Sessions
                  _SectionLabel(
                    'TIME BLOCKS & REMINDERS',
                    subtitle: 'optional',
                    info: 'Each block is one planned work slot.\n'
                        'Add reminders inside each block.',
                  ),
                  const SizedBox(height: 8),
                  _SessionList(
                    sessions: _sessions,
                    savedSessions: widget.task?.sessions,
                    onChanged: (s) => setState(() => _sessions = s),
                  ),
                  const SizedBox(height: 16),

                  // More options
                  GestureDetector(
                    onTap: () => setState(() => _showMore = !_showMore),
                    child: Row(children: [
                      Icon(
                        _showMore
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showMore
                            ? 'Less options'
                            : 'Deadline · Category · Recurrence · Notes',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                    ]),
                  ),
                  if (_showMore) ...[
                    const SizedBox(height: 16),
                    _DeadlinePicker(
                      value: _deadline,
                      onChanged: (d) => setState(() => _deadline = d),
                    ),
                    const SizedBox(height: 14),
                    _CategoryPicker(
                      value: _category,
                      onChanged: (c) => setState(() => _category = c),
                    ),
                    const SizedBox(height: 14),
                    // Recurrence picker
                    _RecurrencePicker(
                      value: _recurrence,
                      options: _recurrenceOptions,
                      onChanged: (r) => setState(() => _recurrence = r),
                    ),
                    const SizedBox(height: 14),
                    _NotesField(ctrl: _descCtrl),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          _buildActionBar(context),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _isCreate ? 'NEW TASK' : 'EDIT TASK',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
      ),
      const Spacer(),
      if (!_isCreate) _StatusBadge(status: _status),
    ]);
  }

  Widget _buildActionBar(BuildContext context) {
    final storage = context.read<StorageService>();
    final notif = context.read<NotificationService>();
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(
            top: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
      ),
      child: Row(children: [
        if (!_isCreate) ...[
          _ActionBtn(
            icon: _status == 'complete'
                ? Icons.undo_rounded
                : Icons.check_circle_outline_rounded,
            label: _status == 'complete' ? 'Reopen' : 'Done',
            color: AppColors.success,
            onTap: () => _toggleComplete(context, storage, notif),
          ),
          const SizedBox(width: 8),
          _ActionBtn(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            color: AppColors.danger,
            onTap: () => _confirmDelete(context, storage, notif),
          ),
          const Spacer(),
        ],
        if (_isCreate)
          Expanded(
            child: _GradientButton(
              label: 'Create Task',
              onTap: () => _save(context, storage, notif),
            ),
          )
        else
          _GradientButton(
            label: 'Save Changes',
            onTap: () => _save(context, storage, notif),
          ),
      ]),
    );
  }

  Future<void> _save(BuildContext context, StorageService storage,
      NotificationService notif) async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Task name is required');
      return;
    }
    setState(() => _error = null);

    final sessions = _sessions
        .map((s) => WorkSession(
              id: 'session_${DateTime.now().millisecondsSinceEpoch}_${s.hashCode}',
              startTime: s.startTime,
              durationMinutes: s.durationMinutes,
              remindersJson:
                  s.reminders.map((r) => r.toModel().toJsonString()).toList(),
            ))
        .toList();

    final now = DateTime.now();
    final taskId = widget.task?.id ?? 'task_${now.millisecondsSinceEpoch}';
    final task = Task(
      id: taskId,
      title: title,
      type: sessions.any((s) => s.startTime != null) ? 'scheduled' : 'flexible',
      deadline: _deadline,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      category: _category,
      subtasks: widget.task?.subtasks ?? [],
      recurrence: _recurrence,
      status: _status,
      snoozeHistory: widget.task?.snoozeHistory ?? [],
      completedAt: _completedAt,
    )..sessions = sessions;

    final wasIncomplete = widget.task?.status != 'complete';
    final nowComplete = _status == 'complete';

    final nav = Navigator.of(context);
    await storage.saveTask(task);

    if (wasIncomplete && nowComplete) {
      final nextTask = RecurrenceUtil.generateNextOccurrence(task);
      if (nextTask != null) {
        await storage.saveTask(nextTask);
        await notif.scheduleTaskReminders(nextTask);
      }
    }

    await notif.cancelTaskAlerts(taskId);
    await notif.scheduleTaskReminders(task);
    if (!mounted) return;
    nav.pop();
  }

  Future<void> _toggleComplete(BuildContext context, StorageService storage,
      NotificationService notif) async {
    setState(() {
      _status = _status == 'complete' ? 'incomplete' : 'complete';
      _completedAt = _status == 'complete' ? DateTime.now() : null;
    });
    await _save(context, storage, notif);
  }

  void _confirmDelete(
      BuildContext context, StorageService storage, NotificationService notif) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Task?',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        content: Text('"${widget.task!.title}" will be permanently deleted.',
            style: GoogleFonts.inter(
                fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              await storage.deleteTask(widget.task!.id);
              await notif.cancelTaskAlerts(widget.task!.id);
              nav.pop();
              nav.pop();
            },
            child: Text('Delete',
                style: GoogleFonts.inter(
                    color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recurrence Picker
// ─────────────────────────────────────────────────────────────────────────────

class _RecurrencePicker extends StatelessWidget {
  final String value;
  final List<(String, String, IconData)> options;
  final ValueChanged<String> onChanged;
  const _RecurrencePicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Repeats',
              style:
                  GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              final selected = value == opt.$1;
              return GestureDetector(
                onTap: () => onChanged(opt.$1),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        selected ? AppColors.accentSoft : AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? AppColors.borderAccent
                          : AppColors.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(opt.$3,
                        size: 12,
                        color: selected
                            ? AppColors.accentPrimary
                            : AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(opt.$2,
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: selected
                                ? AppColors.accentPrimary
                                : AppColors.textSecondary,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Session list
// ─────────────────────────────────────────────────────────────────────────────

class _SessionList extends StatelessWidget {
  final List<_SessionDraft> sessions;
  final List<WorkSession>? savedSessions;
  final ValueChanged<List<_SessionDraft>> onChanged;

  const _SessionList({
    required this.sessions,
    this.savedSessions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ...sessions.asMap().entries.map((e) => _SessionCard(
            index: e.key,
            draft: e.value,
            savedSession:
                (savedSessions != null && e.key < savedSessions!.length)
                    ? savedSessions![e.key]
                    : null,
            onUpdate: (updated) {
              final list = List<_SessionDraft>.from(sessions);
              list[e.key] = updated;
              onChanged(list);
            },
            onRemove: () {
              final list = List<_SessionDraft>.from(sessions)..removeAt(e.key);
              onChanged(list);
            },
          )),
      _AddRowButton(
        label:
            sessions.isEmpty ? 'Add Part 1' : 'Add Part ${sessions.length + 1}',
        icon: Icons.add_circle_outline_rounded,
        onTap: () => onChanged([...sessions, _SessionDraft()]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session card
// ─────────────────────────────────────────────────────────────────────────────

class _SessionCard extends StatefulWidget {
  final int index;
  final _SessionDraft draft;
  final WorkSession? savedSession;
  final ValueChanged<_SessionDraft> onUpdate;
  final VoidCallback onRemove;

  const _SessionCard({
    required this.index,
    required this.draft,
    this.savedSession,
    required this.onUpdate,
    required this.onRemove,
  });

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _expanded = true;
  final _customDurCtrl = TextEditingController();

  String _fmtDur(int mins) {
    if (mins < 60) return '${mins}m';
    if (mins % 60 == 0) return '${mins ~/ 60}h';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    final now = DateTime.now();
    final isToday =
        dt.day == now.day && dt.month == now.month && dt.year == now.year;
    return isToday ? '$h:$m $p' : '${dt.day}/${dt.month} $h:$m $p';
  }

  void _update(
      {DateTime? startTime,
      int? durationMinutes,
      List<_ReminderDraft>? reminders,
      bool clearStart = false,
      bool clearDur = false}) {
    final d = widget.draft;
    widget.onUpdate(_SessionDraft(
      startTime: clearStart ? null : (startTime ?? d.startTime),
      durationMinutes: clearDur ? null : (durationMinutes ?? d.durationMinutes),
      reminders: reminders ?? d.reminders,
    ));
  }

  @override
  void dispose() {
    _customDurCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final hasStart = d.startTime != null;
    final hasEnd = d.endTime != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bgChip,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: AppColors.accentPrimary.withValues(alpha: 0.7),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Part ${widget.index + 1}',
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentPrimary)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _summaryLabel(d),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: hasStart
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (d.reminders.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.notifications_outlined,
                          size: 10, color: AppColors.warning),
                      const SizedBox(width: 3),
                      Text('${d.reminders.length}',
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning)),
                    ]),
                  ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onRemove,
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: AppColors.textMuted),
                ),
              ]),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(
                      color: AppColors.border.withValues(alpha: 0.4),
                      height: 14),

                  // Time row: start + duration
                  Row(children: [
                    Expanded(
                      child: _TimeChip(
                        label: hasStart
                            ? _fmtTime(d.startTime!)
                            : 'Start time (opt)',
                        placeholder: !hasStart,
                        onTap: () async {
                          final p = await _pickDateTime(context, d.startTime);
                          if (p != null) _update(startTime: p);
                        },
                        onClear:
                            hasStart ? () => _update(clearStart: true) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DurationInput(
                        durationMinutes: d.durationMinutes,
                        fmtDur: _fmtDur,
                        onChanged: (v) =>
                            _update(durationMinutes: v, clearDur: v == null),
                      ),
                    ),
                  ]),

                  if (hasEnd)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        'Ends at ${_fmtTime(d.endTime!)}',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.accentPrimary,
                            fontWeight: FontWeight.w500),
                      ),
                    ),

                  const SizedBox(height: 14),

                  Row(children: [
                    const Icon(Icons.notifications_outlined,
                        size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      'REMINDERS FOR PART ${widget.index + 1}',
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 1.1),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  ...d.reminders.asMap().entries.map((e) => _ReminderRow(
                        key: ValueKey('rem_${widget.index}_${e.key}'),
                        draft: e.value,
                        sessionHasStart: hasStart,
                        sessionHasEnd: hasEnd,
                        onUpdate: (updated) {
                          final list = List<_ReminderDraft>.from(d.reminders);
                          list[e.key] = updated;
                          _update(reminders: list);
                        },
                        onRemove: () {
                          final list = List<_ReminderDraft>.from(d.reminders)
                            ..removeAt(e.key);
                          _update(reminders: list);
                        },
                      )),

                  _AddRowButton(
                    label: d.reminders.isEmpty
                        ? 'Add a reminder'
                        : 'Add another reminder',
                    icon: Icons.add_alert_outlined,
                    onTap: () => _update(
                        reminders: [...d.reminders, _ReminderDraft.fresh()]),
                  ),

                  if (widget.savedSession != null)
                    _ReminderHistorySection(session: widget.savedSession!),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _summaryLabel(_SessionDraft d) {
    if (d.startTime == null && d.durationMinutes == null) {
      return d.reminders.isEmpty
          ? 'Free · tap to configure'
          : 'Free · ${d.reminders.length} reminder${d.reminders.length == 1 ? "" : "s"}';
    }
    if (d.startTime != null && d.endTime != null) {
      return '${_fmtTime(d.startTime!)} → ${_fmtTime(d.endTime!)}';
    }
    if (d.startTime != null) return '${_fmtTime(d.startTime!)} · open-ended';
    return '${_fmtDur(d.durationMinutes!)} block · no fixed time';
  }

  Future<DateTime?> _pickDateTime(
      BuildContext context, DateTime? initial) async {
    final base = initial ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => _lightPicker(ctx, child),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      builder: (ctx, child) => _lightPicker(ctx, child),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Widget _lightPicker(BuildContext context, Widget? child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.accentPrimary,
            onPrimary: Colors.white,
            surface: AppColors.bgSecondary,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Duration input — free text entry + quick presets
// ─────────────────────────────────────────────────────────────────────────────

class _DurationInput extends StatefulWidget {
  final int? durationMinutes;
  final String Function(int) fmtDur;
  final ValueChanged<int?> onChanged;

  const _DurationInput({
    required this.durationMinutes,
    required this.fmtDur,
    required this.onChanged,
  });

  @override
  State<_DurationInput> createState() => _DurationInputState();
}

class _DurationInputState extends State<_DurationInput> {
  bool _editing = false;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  static const _presets = [30, 45, 60, 90, 120, 180, 240];

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _ctrl.text = widget.durationMinutes?.toString() ?? '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    final raw = _ctrl.text.trim();
    final mins = int.tryParse(raw);
    widget.onChanged(mins != null && mins > 0 ? mins : null);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isSet = widget.durationMinutes != null;

    if (_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.borderAccent),
            ),
            child: Row(children: [
              const Icon(Icons.timer_outlined,
                  size: 13, color: AppColors.accentPrimary),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.accentPrimary),
                  decoration: InputDecoration(
                    hintText: 'minutes',
                    hintStyle: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.textMuted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    suffixText: 'min',
                    suffixStyle: GoogleFonts.inter(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                  onSubmitted: (_) => _commit(),
                ),
              ),
              GestureDetector(
                onTap: _commit,
                child: const Icon(Icons.check_rounded,
                    size: 14, color: AppColors.accentPrimary),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _presets
                  .map((p) => GestureDetector(
                        onTap: () {
                          widget.onChanged(p);
                          setState(() => _editing = false);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.bgSecondary,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            p < 60
                                ? '${p}m'
                                : (p % 60 == 0
                                    ? '${p ~/ 60}h'
                                    : '${p ~/ 60}h${p % 60}m'),
                            style: GoogleFonts.inter(
                                fontSize: 10, color: AppColors.textSecondary),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: _startEditing,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSet ? AppColors.accentSoft : AppColors.bgChip,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: isSet ? AppColors.borderAccent : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timer_outlined,
              size: 13,
              color: isSet ? AppColors.accentPrimary : AppColors.textMuted),
          const SizedBox(width: 5),
          Text(isSet ? widget.fmtDur(widget.durationMinutes!) : 'Duration',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color:
                      isSet ? AppColors.accentPrimary : AppColors.textMuted)),
          if (isSet) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => widget.onChanged(null),
              child: Icon(Icons.close_rounded,
                  size: 12,
                  color: AppColors.accentPrimary.withValues(alpha: 0.7)),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reminder row — fully inline config
// ─────────────────────────────────────────────────────────────────────────────

class _ReminderRow extends StatefulWidget {
  final _ReminderDraft draft;
  final bool sessionHasStart;
  final bool sessionHasEnd;
  final ValueChanged<_ReminderDraft> onUpdate;
  final VoidCallback onRemove;

  const _ReminderRow({
    super.key,
    required this.draft,
    required this.sessionHasStart,
    required this.sessionHasEnd,
    required this.onUpdate,
    required this.onRemove,
  });

  @override
  State<_ReminderRow> createState() => _ReminderRowState();
}

class _ReminderRowState extends State<_ReminderRow> {
  bool _expanded = false;
  List<TextEditingController> _qCtrls = [];
  bool _editingOffset = false;
  final _offsetCtrl = TextEditingController();

  /// Alert type metadata: (key, icon, label, description)
  static const _alertMeta = [
    (
      'notification',
      Icons.notifications_outlined,
      'Notification',
      'Silent notification badge'
    ),
    ('sound', Icons.volume_up_rounded, 'Sound', 'Notification with sound'),
    (
      'ringtone',
      Icons.ring_volume_rounded,
      'Ringtone',
      'Continuous ringing until dismissed'
    ),
    (
      'callout',
      Icons.record_voice_over_outlined,
      'Callout',
      'TTS speaks task name aloud'
    ),
    (
      'alarm',
      Icons.alarm,
      'Alarm',
      'Fullscreen alarm, bypasses Do Not Disturb'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _syncControllersFromDraft();
  }

  void _syncControllersFromDraft() {
    for (final c in _qCtrls) c.dispose();
    final questions = widget.draft.followUpQuestions;
    _qCtrls = questions.map((q) => TextEditingController(text: q)).toList();
  }

  @override
  void didUpdateWidget(_ReminderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.draft.followUpQuestions.length != _qCtrls.length) {
      _syncControllersFromDraft();
    }
  }

  @override
  void dispose() {
    for (final c in _qCtrls) c.dispose();
    _offsetCtrl.dispose();
    super.dispose();
  }

  void _update(_ReminderDraft updated) => widget.onUpdate(updated);

  List<String> get _currentQuestions => _qCtrls.map((c) => c.text).toList();

  void _addQuestion() {
    setState(() => _qCtrls.add(TextEditingController()));
    _update(_ReminderDraft(
      triggerMode: widget.draft.triggerMode,
      offsetMinutes: widget.draft.offsetMinutes,
      absoluteTime: widget.draft.absoluteTime,
      alertTypes: widget.draft.alertTypes,
      followUpQuestions: [
        ..._currentQuestions.where((q) => q.trim().isNotEmpty),
        ''
      ],
      customRingtonePath: widget.draft.customRingtonePath,
    ));
  }

  void _removeQuestion(int index) {
    _qCtrls[index].dispose();
    setState(() => _qCtrls.removeAt(index));
    final qs = List<String>.from(widget.draft.followUpQuestions)
      ..removeAt(index);
    _update(_ReminderDraft(
      triggerMode: widget.draft.triggerMode,
      offsetMinutes: widget.draft.offsetMinutes,
      absoluteTime: widget.draft.absoluteTime,
      alertTypes: widget.draft.alertTypes,
      followUpQuestions: qs,
      customRingtonePath: widget.draft.customRingtonePath,
    ));
  }

  void _onQuestionChanged(int index, String value) {
    final qs = List<String>.from(widget.draft.followUpQuestions);
    while (qs.length <= index) qs.add('');
    qs[index] = value;
    _update(_ReminderDraft(
      triggerMode: widget.draft.triggerMode,
      offsetMinutes: widget.draft.offsetMinutes,
      absoluteTime: widget.draft.absoluteTime,
      alertTypes: widget.draft.alertTypes,
      followUpQuestions: qs,
      customRingtonePath: widget.draft.customRingtonePath,
    ));
  }

  Future<void> _pickAbsoluteTime(BuildContext context) async {
    final d = widget.draft;
    final base = d.absoluteTime ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => _picker(ctx, child),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      builder: (ctx, child) => _picker(ctx, child),
    );
    if (time == null) return;
    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    _update(_ReminderDraft(
      triggerMode: d.triggerMode,
      offsetMinutes: d.offsetMinutes,
      absoluteTime: picked,
      alertTypes: d.alertTypes,
      followUpQuestions: d.followUpQuestions,
      customRingtonePath: d.customRingtonePath,
    ));
  }

  Future<void> _pickCustomRingtone() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'aac', 'ogg', 'm4a', 'wav'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      _update(_ReminderDraft(
        triggerMode: widget.draft.triggerMode,
        offsetMinutes: widget.draft.offsetMinutes,
        absoluteTime: widget.draft.absoluteTime,
        alertTypes: widget.draft.alertTypes,
        followUpQuestions: widget.draft.followUpQuestions,
        customRingtonePath: path,
      ));
    } catch (e) {
      debugPrint('FilePicker error: $e');
    }
  }

  Widget _picker(BuildContext context, Widget? child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.accentPrimary,
            onPrimary: Colors.white,
            surface: AppColors.bgSecondary,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
      ),
      child: Column(children: [
        // Collapsed row
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(children: [
              const Icon(Icons.alarm_outlined,
                  size: 14, color: AppColors.accentPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _buildLabel(d),
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: _alertMeta
                    .where((m) => d.alertTypes.contains(m.$1))
                    .map((m) => Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(m.$2,
                              size: 13, color: AppColors.accentPrimary),
                        ))
                    .toList(),
              ),
              const SizedBox(width: 6),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: widget.onRemove,
                child: const Icon(Icons.close_rounded,
                    size: 14, color: AppColors.textMuted),
              ),
            ]),
          ),
        ),

        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(
                    color: AppColors.border.withValues(alpha: 0.4), height: 12),

                // When
                _configLabel('When'),
                const SizedBox(height: 6),
                _buildTriggerChips(d),

                // Absolute time picker
                if (d.triggerMode == 'absolute') ...[
                  const SizedBox(height: 10),
                  _configLabel('Fire at'),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _pickAbsoluteTime(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: d.absoluteTime != null
                            ? AppColors.accentSoft
                            : AppColors.bgSecondary,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: d.absoluteTime != null
                              ? AppColors.borderAccent
                              : AppColors.border.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.access_time_rounded,
                            size: 14,
                            color: d.absoluteTime != null
                                ? AppColors.accentPrimary
                                : AppColors.textMuted),
                        const SizedBox(width: 6),
                        Text(
                          d.absoluteTime != null
                              ? _fmtAbsolute(d.absoluteTime!)
                              : 'Tap to pick date & time',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: d.absoluteTime != null
                                ? AppColors.accentPrimary
                                : AppColors.textMuted,
                          ),
                        ),
                        if (d.absoluteTime != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _update(_ReminderDraft(
                              triggerMode: d.triggerMode,
                              offsetMinutes: d.offsetMinutes,
                              absoluteTime: null,
                              alertTypes: d.alertTypes,
                              followUpQuestions: d.followUpQuestions,
                              customRingtonePath: d.customRingtonePath,
                            )),
                            child: const Icon(Icons.close_rounded,
                                size: 13, color: AppColors.textMuted),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ],

                // How far — free entry + quick chips
                if (d.triggerMode != 'absolute') ...[
                  const SizedBox(height: 10),
                  _configLabel('How far before/after'),
                  const SizedBox(height: 6),
                  _OffsetInput(
                    offsetMinutes: d.offsetMinutes,
                    onChanged: (v) => _update(_ReminderDraft(
                      triggerMode: d.triggerMode,
                      offsetMinutes: v,
                      absoluteTime: d.absoluteTime,
                      alertTypes: d.alertTypes,
                      followUpQuestions: d.followUpQuestions,
                      customRingtonePath: d.customRingtonePath,
                    )),
                  ),
                ],

                // Alert types
                const SizedBox(height: 10),
                _configLabel('Alert type'),
                const SizedBox(height: 6),
                Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _alertMeta.map((m) {
                      final active = d.alertTypes.contains(m.$1);
                      return Tooltip(
                        message: m.$4,
                        child: GestureDetector(
                          onTap: () {
                            final next = List<String>.from(d.alertTypes);
                            active ? next.remove(m.$1) : next.add(m.$1);
                            // 'silent' is a synonym for 'notification' — keep at least one
                            if (next.isEmpty) next.add('notification');
                            // Mutually exclusive: if alarm is selected, remove ringtone; if ringtone, remove alarm
                            if (m.$1 == 'alarm' && !active)
                              next.remove('ringtone');
                            if (m.$1 == 'ringtone' && !active)
                              next.remove('alarm');
                            _update(_ReminderDraft(
                              triggerMode: d.triggerMode,
                              offsetMinutes: d.offsetMinutes,
                              absoluteTime: d.absoluteTime,
                              alertTypes: next,
                              followUpQuestions: d.followUpQuestions,
                              customRingtonePath: d.customRingtonePath,
                            ));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.accentPrimary
                                      .withValues(alpha: 0.12)
                                  : AppColors.bgSecondary,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: active
                                    ? AppColors.accentPrimary
                                        .withValues(alpha: 0.4)
                                    : AppColors.border.withValues(alpha: 0.4),
                              ),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(m.$2,
                                  size: 12,
                                  color: active
                                      ? AppColors.accentPrimary
                                      : AppColors.textMuted),
                              const SizedBox(width: 4),
                              Text(m.$3,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: active
                                        ? AppColors.accentPrimary
                                        : AppColors.textMuted,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  )),
                            ]),
                          ),
                        ),
                      );
                    }).toList()),

                // Custom ringtone — shown when ringtone or alarm is selected
                if (d.alertTypes.contains('ringtone') ||
                    d.alertTypes.contains('alarm')) ...[
                  const SizedBox(height: 10),
                  _configLabel('Custom ringtone (optional)'),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickCustomRingtone,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: d.customRingtonePath != null
                            ? AppColors.accentSoft
                            : AppColors.bgSecondary,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: d.customRingtonePath != null
                              ? AppColors.borderAccent
                              : AppColors.border.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.music_note_outlined,
                            size: 13,
                            color: d.customRingtonePath != null
                                ? AppColors.accentPrimary
                                : AppColors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            d.customRingtonePath != null
                                ? d.customRingtonePath!.split('/').last
                                : 'Upload MP3 / AAC / OGG…',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: d.customRingtonePath != null
                                  ? AppColors.accentPrimary
                                  : AppColors.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (d.customRingtonePath != null)
                          GestureDetector(
                            onTap: () => _update(_ReminderDraft(
                              triggerMode: d.triggerMode,
                              offsetMinutes: d.offsetMinutes,
                              absoluteTime: d.absoluteTime,
                              alertTypes: d.alertTypes,
                              followUpQuestions: d.followUpQuestions,
                              customRingtonePath: null,
                            )),
                            child: const Icon(Icons.close_rounded,
                                size: 13, color: AppColors.textMuted),
                          ),
                      ]),
                    ),
                  ),
                ],

                // Follow-up questions
                const SizedBox(height: 10),
                _configLabel('Follow-up questions (optional)'),
                const SizedBox(height: 5),
                ...List.generate(
                    _qCtrls.length,
                    (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.bgSecondary,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.border
                                          .withValues(alpha: 0.5)),
                                ),
                                child: TextField(
                                  controller: _qCtrls[i],
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.textPrimary),
                                  decoration: InputDecoration(
                                    hintText: i == 0
                                        ? 'e.g. "Did you complete {task_name}?"'
                                        : 'Another question…',
                                    hintStyle: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: AppColors.textMuted),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                  ),
                                  onChanged: (v) => _onQuestionChanged(i, v),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _removeQuestion(i),
                              child: const Icon(Icons.remove_circle_outline,
                                  size: 16, color: AppColors.textMuted),
                            ),
                          ]),
                        )),
                GestureDetector(
                  onTap: _addQuestion,
                  child: Row(children: [
                    const Icon(Icons.add_circle_outline,
                        size: 13, color: AppColors.accentPrimary),
                    const SizedBox(width: 4),
                    Text(
                      _qCtrls.isEmpty
                          ? 'Add follow-up question'
                          : 'Add another question',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.accentPrimary),
                    ),
                  ]),
                ),
                const SizedBox(height: 3),
                Text(
                  'Use {task_name} to auto-insert the task title.',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _configLabel(String text) => Text(text,
      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted));

  Widget _buildTriggerChips(_ReminderDraft d) {
    final options = <String, String>{
      if (widget.sessionHasStart) 'before_start': 'Before start',
      if (widget.sessionHasStart) 'after_start': 'After start',
      if (widget.sessionHasEnd) 'before_end': 'Before end',
      'absolute': 'Specific time',
    };
    if (options.isEmpty) {
      return Text(
        'Add a start time to this block to use offset reminders.',
        style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.entries
          .map((e) => GestureDetector(
                onTap: () => _update(_ReminderDraft(
                  triggerMode: e.key,
                  offsetMinutes: d.offsetMinutes,
                  absoluteTime: d.absoluteTime,
                  alertTypes: d.alertTypes,
                  followUpQuestions: d.followUpQuestions,
                  customRingtonePath: d.customRingtonePath,
                )),
                child: _Chip(label: e.value, selected: d.triggerMode == e.key),
              ))
          .toList(),
    );
  }

  String _buildLabel(_ReminderDraft d) {
    if (d.triggerMode == 'absolute' && d.absoluteTime != null) {
      return 'At ${_fmtAbsolute(d.absoluteTime!)}';
    }
    if (d.triggerMode == 'absolute') return 'At specific time (tap to set)';
    final mins = d.offsetMinutes ?? 15;
    final t = mins < 60
        ? '${mins}m'
        : (mins % 60 == 0 ? '${mins ~/ 60}h' : '${mins ~/ 60}h ${mins % 60}m');
    switch (d.triggerMode) {
      case 'before_start':
        return '$t before start';
      case 'after_start':
        return '$t after start';
      case 'before_end':
        return '$t before end';
      default:
        return '$t before start';
    }
  }

  String _fmtAbsolute(DateTime dt) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final now = DateTime.now();
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$h:$m $p';
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return 'Today · $timeStr';
    }
    return '${dt.day} ${months[dt.month]} · $timeStr';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offset input — free text + preset chips
// ─────────────────────────────────────────────────────────────────────────────

class _OffsetInput extends StatefulWidget {
  final int? offsetMinutes;
  final ValueChanged<int?> onChanged;
  const _OffsetInput({required this.offsetMinutes, required this.onChanged});

  @override
  State<_OffsetInput> createState() => _OffsetInputState();
}

class _OffsetInputState extends State<_OffsetInput> {
  bool _editing = false;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  static const _presets = [5, 10, 15, 30, 60, 120];
  static const _presetLabels = ['5m', '10m', '15m', '30m', '1h', '2h'];

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() {
      _editing = true;
      _ctrl.text = widget.offsetMinutes?.toString() ?? '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    final v = int.tryParse(_ctrl.text.trim());
    widget.onChanged(v != null && v > 0 ? v : widget.offsetMinutes);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...List.generate(
                _presets.length,
                (i) => GestureDetector(
                      onTap: () => widget.onChanged(_presets[i]),
                      child: _Chip(
                        label: _presetLabels[i],
                        selected:
                            widget.offsetMinutes == _presets[i] && !_editing,
                      ),
                    )),
            // Custom entry chip
            GestureDetector(
              onTap: _editing ? null : _startEdit,
              child: _Chip(
                label: _editing
                    ? 'typing…'
                    : (widget.offsetMinutes != null &&
                            !_presets.contains(widget.offsetMinutes)
                        ? '${widget.offsetMinutes}m ✎'
                        : 'Custom…'),
                selected: _editing ||
                    (widget.offsetMinutes != null &&
                        !_presets.contains(widget.offsetMinutes)),
              ),
            ),
          ],
        ),
        if (_editing) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderAccent),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.accentPrimary),
                  decoration: InputDecoration(
                    hintText: 'enter minutes',
                    hintStyle: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.textMuted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    suffixText: 'min',
                    suffixStyle: GoogleFonts.inter(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                  onSubmitted: (_) => _commit(),
                ),
              ),
              GestureDetector(
                onTap: _commit,
                child: const Icon(Icons.check_rounded,
                    size: 14, color: AppColors.accentPrimary),
              ),
            ]),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              color: AppColors.border, borderRadius: BorderRadius.circular(8)),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final String? subtitle;
  final String? info;
  const _SectionLabel(this.text, {this.subtitle, this.info});

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(text,
            style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 1.2)),
        if (subtitle != null) ...[
          const SizedBox(width: 6),
          Text('· $subtitle',
              style:
                  GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted)),
        ],
        if (info != null) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: info,
            child: const Icon(Icons.info_outline_rounded,
                size: 12, color: AppColors.textMuted),
          ),
        ],
      ]);
}

class _TitleField extends StatelessWidget {
  final TextEditingController ctrl;
  final String? error;
  const _TitleField({required this.ctrl, this.error});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: error != null
                    ? AppColors.danger.withValues(alpha: 0.6)
                    : AppColors.borderAccent.withValues(alpha: 0.5),
              ),
            ),
            child: TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 1,
              style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Task name…',
                hintStyle: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(error!,
                  style:
                      GoogleFonts.inter(fontSize: 11, color: AppColors.danger)),
            ),
        ],
      );
}

class _TimeChip extends StatelessWidget {
  final String label;
  final bool placeholder;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _TimeChip({
    required this.label,
    required this.placeholder,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: placeholder ? AppColors.bgChip : AppColors.accentSoft,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: placeholder ? AppColors.border : AppColors.borderAccent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.schedule_outlined,
                size: 13,
                color: placeholder
                    ? AppColors.textMuted
                    : AppColors.accentPrimary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: placeholder
                          ? AppColors.textMuted
                          : AppColors.accentPrimary)),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close_rounded,
                    size: 12,
                    color: AppColors.accentPrimary.withValues(alpha: 0.7)),
              ),
            ],
          ]),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  const _Chip({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.borderAccent
                : AppColors.border.withValues(alpha: 0.5),
          ),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? AppColors.accentPrimary
                    : AppColors.textSecondary)),
      );
}

class _AddRowButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _AddRowButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.border.withValues(alpha: 0.4),
                style: BorderStyle.solid),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
      );
}

class _DeadlinePicker extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  const _DeadlinePicker({this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now().add(const Duration(days: 1)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (ctx, child) => _picker(ctx, child),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: value != null
              ? TimeOfDay.fromDateTime(value!)
              : const TimeOfDay(hour: 23, minute: 59),
          builder: (ctx, child) => _picker(ctx, child),
        );
        if (time == null) return;
        onChanged(
            DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value != null
              ? AppColors.danger.withValues(alpha: 0.08)
              : AppColors.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value != null
                ? AppColors.danger.withValues(alpha: 0.3)
                : AppColors.border.withValues(alpha: 0.5),
          ),
        ),
        child: Row(children: [
          Icon(Icons.flag_outlined,
              size: 15,
              color: value != null ? AppColors.danger : AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value != null ? _fmt(value!) : 'Set deadline (optional)',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color:
                      value != null ? AppColors.danger : AppColors.textMuted),
            ),
          ),
          if (value != null)
            GestureDetector(
              onTap: () => onChanged(null),
              child: const Icon(Icons.close_rounded,
                  size: 15, color: AppColors.textMuted),
            ),
        ]),
      ),
    );
  }

  String _fmt(DateTime dt) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month]} · $h:$m $p';
  }

  Widget _picker(BuildContext context, Widget? child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.danger,
            onPrimary: Colors.white,
            surface: AppColors.bgSecondary,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      );
}

class _CategoryPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _CategoryPicker({this.value, required this.onChanged});

  static const _cats = ['Work', 'Personal', 'College', 'Health', 'Other'];
  static const _catIcons = [
    Icons.work_outline,
    Icons.person_outline,
    Icons.school_outlined,
    Icons.favorite_outline,
    Icons.category_outlined,
  ];

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Category',
              style:
                  GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
                _cats.length,
                (i) => GestureDetector(
                      onTap: () =>
                          onChanged(value == _cats[i] ? null : _cats[i]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: value == _cats[i]
                              ? AppColors.accentSoft
                              : AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: value == _cats[i]
                                ? AppColors.borderAccent
                                : AppColors.border.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_catIcons[i],
                              size: 12,
                              color: value == _cats[i]
                                  ? AppColors.accentPrimary
                                  : AppColors.textMuted),
                          const SizedBox(width: 5),
                          Text(_cats[i],
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: value == _cats[i]
                                      ? AppColors.accentPrimary
                                      : AppColors.textSecondary,
                                  fontWeight: value == _cats[i]
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                        ]),
                      ),
                    )),
          ),
        ],
      );
}

class _NotesField extends StatelessWidget {
  final TextEditingController ctrl;
  const _NotesField({required this.ctrl});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notes',
              style:
                  GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            ),
            child: TextField(
              controller: ctrl,
              maxLines: 3,
              style:
                  GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Any notes…',
                hintStyle:
                    GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ],
      );
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GradientButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.accentShadow,
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final done = status == 'complete';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (done ? AppColors.success : AppColors.warning)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (done ? AppColors.success : AppColors.warning)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        done ? 'Done ✓' : 'Pending',
        style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: done ? AppColors.success : AppColors.warning),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reminder history section
// ─────────────────────────────────────────────────────────────────────────────

class _ReminderHistorySection extends StatelessWidget {
  final WorkSession session;
  const _ReminderHistorySection({required this.session});

  @override
  Widget build(BuildContext context) {
    final events = <({String question, String? answer, DateTime firedAt})>[];
    for (final reminder in session.reminders) {
      for (final event in reminder.history) {
        events.add((
          question:
              event.question ?? reminder.followUpQuestion ?? 'Reminder fired',
          answer: event.answer,
          firedAt: event.firedAt,
        ));
      }
    }
    if (events.isEmpty) return const SizedBox.shrink();
    events.sort((a, b) => b.firedAt.compareTo(a.firedAt));

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.history_outlined,
                size: 11, color: AppColors.textMuted),
            const SizedBox(width: 5),
            Text('FOLLOW-UP HISTORY',
                style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 1.1)),
          ]),
          const SizedBox(height: 6),
          ...events.take(5).map((e) => _HistoryEventRow(
                question: e.question,
                answer: e.answer,
                firedAt: e.firedAt,
              )),
          if (events.length > 5)
            Text('+${events.length - 5} older events',
                style: GoogleFonts.inter(
                    fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _HistoryEventRow extends StatelessWidget {
  final String question;
  final String? answer;
  final DateTime firedAt;

  const _HistoryEventRow({
    required this.question,
    required this.answer,
    required this.firedAt,
  });

  @override
  Widget build(BuildContext context) {
    final answered = answer != null;
    final isYes = answer == 'yes';
    final color = !answered
        ? AppColors.textMuted
        : isYes
            ? AppColors.success
            : AppColors.danger;
    final icon = !answered
        ? Icons.remove_circle_outline
        : isYes
            ? Icons.check_circle_outline
            : Icons.cancel_outlined;
    final label = !answered ? 'No answer' : (isYes ? 'Yes' : 'No');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            question.length > 40 ? '${question.substring(0, 40)}…' : question,
            style:
                GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(' $label · ${_fmtDate(firedAt)}',
            style: GoogleFonts.inter(
                fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  String _fmtDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final p = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $p';
    }
    return '${dt.day}/${dt.month}';
  }
}

// Legacy alias
class TaskDetailBottomSheet {
  static Future<void> show(BuildContext context, Task task) =>
      TaskSheet.showEdit(context, task);
}
