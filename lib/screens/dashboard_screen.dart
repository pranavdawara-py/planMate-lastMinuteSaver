import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../models/task.dart';
import '../models/work_session.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../utils/task_completion_util.dart';
import '../widgets/task_detail_bottom_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with AutomaticKeepAliveClientMixin {
  bool _overdueExpanded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<StorageService>(
      builder: (context, storage, _) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final allTasks = storage.getTasks();
        final todaysTasks = allTasks
            .where((t) =>
                t.status == 'incomplete' && _taskIsOnDay(t, today))
            .toList();
        final overdueTasks = allTasks
            .where((t) =>
                t.status == 'incomplete' && _isOverdue(t, today))
            .toList();
        final undatedTasks = allTasks
            .where((t) =>
                t.status == 'incomplete' &&
                t.sessions.isEmpty &&
                t.deadline == null)
            .toList();

        final totalToday =
            allTasks.where((t) => _taskIsOnDay(t, today)).length;
        final completedToday = allTasks
            .where((t) =>
                t.status == 'complete' && _taskIsOnDay(t, today))
            .length;

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          floatingActionButton: _buildGradientFAB(context),
          body: RefreshIndicator(
            onRefresh: () async => setState(() {}),
            color: AppColors.accentPrimary,
            backgroundColor: AppColors.bgSecondary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                _buildGreetingHeader(now),
                const SizedBox(height: 16),
                _buildProgressSection(completedToday, totalToday),
                const SizedBox(height: 16),
                if (overdueTasks.isNotEmpty) ...[
                  _buildOverdueCard(overdueTasks),
                  const SizedBox(height: 14),
                ],
                _buildTodayCard(todaysTasks, storage),
                if (undatedTasks.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _buildUndatedCard(undatedTasks),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  bool _taskIsOnDay(Task t, DateTime day) {
    if (t.sessionsOnDay(day).isNotEmpty) return true;
    if (t.deadline != null) {
      final d =
          DateTime(t.deadline!.year, t.deadline!.month, t.deadline!.day);
      return d == day;
    }
    return false;
  }

  bool _isOverdue(Task t, DateTime today) {
    final hasFutureOrTodaySession = t.timedSessions.any((s) {
      final d = DateTime(
          s.startTime!.year, s.startTime!.month, s.startTime!.day);
      return !d.isBefore(today);
    });
    if (hasFutureOrTodaySession) return false;
    if (t.deadline != null) return t.deadline!.isBefore(today);
    final lastStart = t.firstSessionStart;
    if (lastStart != null) {
      final d =
          DateTime(lastStart.year, lastStart.month, lastStart.day);
      return d.isBefore(today);
    }
    return false;
  }

  Widget _buildGreetingHeader(DateTime now) {
    final hour = now.hour;
    final emoji =
        hour < 6 ? '🌙' : hour < 12 ? '☀️' : hour < 17 ? '🌤️' : '🌙';
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    final dateLabel =
        '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$emoji $greeting',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateLabel,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressSection(int completed, int total) {
    final pct = total == 0 ? 0.0 : completed / total;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: pct),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, value, __) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Today's Progress",
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          total == 0
                              ? 'No tasks yet ✨'
                              : '$completed of $total done',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (total > 0 && completed == total) ...[
                          const SizedBox(height: 3),
                          Text(
                            '🎉 All done! Great work!',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Arc ring
                  SizedBox(
                    width: 68,
                    height: 68,
                    child: CustomPaint(
                      painter: _ArcRingPainter(
                        progress: value,
                        bgColor: AppColors.borderSubtle,
                        fgColor: value >= 1.0
                            ? AppColors.success
                            : AppColors.accentPrimary,
                        fgColor2: value >= 1.0
                            ? AppColors.success
                            : AppColors.accentCoral,
                        glowColor: value >= 1.0
                            ? AppColors.success.withValues(alpha: 0.20)
                            : AppColors.accentGlow,
                      ),
                      child: Center(
                        child: Text(
                          '${(value * 100).round()}%',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: AppColors.borderSubtle,
                  valueColor: AlwaysStoppedAnimation(
                    value >= 1.0
                        ? AppColors.success
                        : AppColors.accentPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverdueCard(List<Task> tasks) {
    final visible =
        _overdueExpanded ? tasks : tasks.take(3).toList();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
        border: Border(
          left: BorderSide(
              color: AppColors.danger.withValues(alpha: 0.55), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.danger, size: 15),
                const SizedBox(width: 6),
                Text(
                  'Overdue (${tasks.length})',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                    letterSpacing: 0.1,
                  ),
                ),
                const Spacer(),
                if (tasks.length > 3)
                  GestureDetector(
                    onTap: () => setState(
                        () => _overdueExpanded = !_overdueExpanded),
                    child: Text(
                      _overdueExpanded ? 'Show less' : 'Show all',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
          ),
          ...visible.map((t) => _buildCompactTaskTile(t, AppColors.danger)),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildTodayCard(List<Task> tasks, StorageService storage) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.today_rounded,
                      color: Colors.white, size: 14),
                ),
                const SizedBox(width: 10),
                Text(
                  "Today's Tasks",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 7),
                if (tasks.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          AppColors.accentPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentPrimary),
                    ),
                  ),
              ],
            ),
          ),
          if (tasks.isEmpty)
            _buildEmptyState()
          else
            ...tasks.map((t) => _buildTaskCard(t, storage)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          Text('🎉', style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All clear for today!',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary),
                ),
                Text(
                  'Add tasks with + or chat with AI.',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUndatedCard(List<Task> tasks) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accentPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
        border: Border(
          left: BorderSide(
              color: AppColors.accentPrimary.withValues(alpha: 0.4),
              width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.inbox_outlined,
                    color: AppColors.accentPrimary, size: 15),
                const SizedBox(width: 6),
                Text(
                  'Unscheduled (${tasks.length})',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentPrimary,
                  ),
                ),
              ],
            ),
          ),
          ...tasks.map((t) =>
              _buildCompactTaskTile(t, AppColors.accentPrimary)),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Task t, StorageService storage) {
    final isOverdueNow =
        t.deadline != null && t.deadline!.isBefore(DateTime.now());
    final catColor = AppColors.categoryColor(t.category);
    final catBg = AppColors.categoryBg(t.category);
    final sessionLabel =
        t.sessions.isNotEmpty ? t.sessions.first.label : null;
    return GestureDetector(
      onTap: () => TaskDetailBottomSheet.show(context, t),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 3, 12, 3),
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
              color: isOverdueNow ? AppColors.danger : catColor,
              width: 3,
            ),
          ),
        ),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Complete button
              GestureDetector(
                onTap: () async {
                  final createdNext = await TaskCompletionUtil.toggleComplete(
                    t, storage, context.read<NotificationService>());
                  if (createdNext && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ Next ${t.recurrence} task scheduled'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: catColor.withValues(alpha: 0.7), width: 2),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sessionLabel != null || t.deadline != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        sessionLabel ??
                            'Due ${_deadlineStr(t.deadline!)}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: isOverdueNow
                              ? AppColors.danger
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (t.reminders.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_outlined,
                          size: 10,
                          color:
                              AppColors.warning.withValues(alpha: 0.8)),
                      const SizedBox(width: 2),
                      Text('${t.reminders.length}',
                          style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning
                                  .withValues(alpha: 0.8))),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (t.category != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: catBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(t.category!,
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: catColor)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactTaskTile(Task t, Color accentColor) {
    return GestureDetector(
      onTap: () => TaskDetailBottomSheet.show(context, t),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
        child: Row(children: [
          Icon(Icons.radio_button_unchecked,
              size: 13, color: accentColor.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(t.title,
                style: GoogleFonts.inter(
                    fontSize: 13, color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (t.deadline != null)
            Text(_deadlineStr(t.deadline!),
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppColors.danger)),
        ]),
      ),
    );
  }

  Widget _buildGradientFAB(BuildContext context) {
    return GestureDetector(
      onTap: () => TaskSheet.showCreate(context),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          shape: BoxShape.circle,
          boxShadow: AppColors.accentShadow,
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
    );
  }

  String _timeStr(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _deadlineStr(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'today ${_timeStr(dt)}';
    return '${dt.day}/${dt.month}';
  }
}

class _ArcRingPainter extends CustomPainter {
  final double progress;
  final Color bgColor;
  final Color fgColor;
  final Color? fgColor2;
  final Color glowColor;

  const _ArcRingPainter({
    required this.progress,
    required this.bgColor,
    required this.fgColor,
    this.fgColor2,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 7.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth / 2;
    const startAngle = -3.14159 / 2;
    const fullSweep = 2 * 3.14159;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      fullSweep,
      false,
      Paint()
        ..color = bgColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (progress <= 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      fullSweep * progress,
      false,
      Paint()
        ..color = glowColor
        ..strokeWidth = strokeWidth + 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    final fgPaint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (fgColor2 != null) {
      fgPaint.shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + fullSweep * progress,
        colors: [fgColor, fgColor2!],
      ).createShader(rect);
    } else {
      fgPaint.color = fgColor;
    }

    canvas.drawArc(rect, startAngle, fullSweep * progress, false, fgPaint);
  }

  @override
  bool shouldRepaint(_ArcRingPainter old) =>
      old.progress != progress ||
      old.fgColor != fgColor ||
      old.fgColor2 != fgColor2;
}
