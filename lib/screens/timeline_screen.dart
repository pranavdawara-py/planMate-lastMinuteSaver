import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../models/task.dart';
import '../models/work_session.dart';
import '../models/task_reminder.dart';
import '../models/fixed_block.dart';
import '../models/day_label.dart';
import '../services/storage_service.dart';
import '../widgets/task_detail_bottom_sheet.dart';

/// Pairs a WorkSession with its parent Task for timeline rendering.
typedef _SessionEntry = ({Task task, WorkSession session});

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen>
    with AutomaticKeepAliveClientMixin {
  DateTime _selectedDay = DateTime.now();

  // Tap-to-reveal timestamps: key = 'sessionId_start'/'sessionId_end', value = (label, x)
  final Map<String, ({String label, double x})> _revealedTimestamps = {};

  // Layout constants
  static const double _hourWidth = 120.0;
  static const double _timeAxisHeight = 36.0;
  static const double _rowHeight = 56.0;
  static const double _minTaskWidth = 44.0;

  @override
  bool get wantKeepAlive => true;

  void _prevDay() =>
      setState(() => _selectedDay = _selectedDay.subtract(const Duration(days: 1)));
  void _nextDay() =>
      setState(() => _selectedDay = _selectedDay.add(const Duration(days: 1)));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<StorageService>(builder: (context, storage, _) {
      final tasks = storage.getTasks();
      final blocks = storage.getFixedBlocks();
      final labels = storage.getDayLabels();

      final dayStr = _dateStr(_selectedDay);
      final dayLabel = labels.where((l) => l.date == dayStr).firstOrNull;

      // ── Tasks with sessions on this day ──────────────────────────────────
      final dayEntries = <_SessionEntry>[];
      for (final task in tasks) {
        for (final session in task.sessionsOnDay(_selectedDay)) {
          dayEntries.add((task: task, session: session));
        }
      }

      // ── Fixed blocks for this day ─────────────────────────────────────────
      final dayBlocks = blocks.where((b) => _blockAppliesToDay(b, _selectedDay)).toList();

      // ── Flexible tasks (no sessions at all) ───────────────────────────────
      // Only show on: the exact deadline day, OR today (for tasks with no deadline).
      // This prevents cluttering every single day's view with all undated tasks.
      final isSelectedDayToday = _isSameDay(_selectedDay, DateTime.now());
      final flexibleTasks = tasks
          .where((t) {
            if (t.sessions.isNotEmpty) return false; // has sessions → not flexible
            if (t.deadline != null) {
              // Show on the deadline day only
              return _isSameDay(t.deadline!, _selectedDay);
            }
            // No deadline → show only on today
            return isSelectedDayToday;
          })
          .toList()
        ..sort((a, b) {
          // Tasks with reminders first, then deadline tasks, then pure flexible
          final aScore = (a.reminders.isNotEmpty ? 2 : 0) +
              (a.deadline != null ? 1 : 0);
          final bScore = (b.reminders.isNotEmpty ? 2 : 0) +
              (b.deadline != null ? 1 : 0);
          return bScore.compareTo(aScore);
        });

      // ── Determine day start hour ──────────────────────────────────────────
      int startHour = 8;
      for (final entry in dayEntries) {
        final h = entry.session.startTime?.hour ?? 8;
        if (h < startHour) startHour = h;
      }
      for (final b in dayBlocks) {
        final h = int.tryParse(b.startTime.split(':')[0]) ?? 8;
        if (h < startHour) startHour = h;
      }
      if (startHour < 6) startHour = 6;

      // ── Current time for red line ─────────────────────────────────────────
      final now = DateTime.now();
      final isToday = _isSameDay(_selectedDay, now);
      final currentTimeX = isToday
          ? (now.hour - startHour) * _hourWidth + (now.minute / 60.0) * _hourWidth
          : null;

      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        floatingActionButton: _buildGradientFAB(),
        body: Column(
          children: [
            _buildDaySelector(dayLabel, isToday),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Main horizontal timeline ──────────────────────────
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildMainTimeline(
                          dayEntries, dayBlocks, startHour, currentTimeX),
                    ),

                    // ── Flexible / unscheduled tasks ──────────────────────
                    if (flexibleTasks.isNotEmpty) ...[
                      _buildSectionDivider('Unscheduled Tasks',
                          count: flexibleTasks.length),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Column(
                          children: flexibleTasks
                              .map((t) => _buildFlexChip(t))
                              .toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gradient FAB
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildGradientFAB() {
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

  // ─────────────────────────────────────────────────────────────────────────
  // Tap-to-reveal timestamp
  // ─────────────────────────────────────────────────────────────────────────

  void _revealTimestamp(String key, double x, DateTime time) {
    final label =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    setState(() => _revealedTimestamps[key] = (label: label, x: x));
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _revealedTimestamps.remove(key));
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Day selector header
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDaySelector(DayLabel? label, bool isToday) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        boxShadow: AppColors.subtleShadow,
        border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.8))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left,
                    color: AppColors.textSecondary),
                onPressed: _prevDay,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDay,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                    builder: (ctx, child) => Theme(
                      data: ThemeData.light().copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: AppColors.accentPrimary,
                          onPrimary: Colors.white,
                          surface: AppColors.bgSecondary,
                          onSurface: AppColors.textPrimary,
                        ),
                        dialogBackgroundColor: AppColors.bgSecondary,
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) setState(() => _selectedDay = picked);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isToday
                        ? AppColors.accentPrimary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isToday
                        ? Border.all(
                            color: AppColors.accentPrimary.withValues(alpha: 0.3))
                        : null,
                  ),
                  child: Text(
                    isToday
                        ? 'Today — ${_fullDateStr(_selectedDay)}'
                        : _fullDateStr(_selectedDay),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isToday
                          ? AppColors.accentPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary),
                onPressed: _nextDay,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.accentPrimary.withValues(alpha: 0.25)),
                ),
                child: Text('📌 ${label.label}',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.accentPrimary)),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Main timeline canvas
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMainTimeline(
    List<_SessionEntry> entries,
    List<FixedBlock> blocks,
    int startHour,
    double? currentTimeX,
  ) {
    // Layout sessions into rows (avoid overlap)
    final rows = _layoutIntoRows(entries);
    final numRows = rows.isEmpty ? 1 : rows.length;

    const int endHour = 24;
    final totalHours = endHour - startHour;
    final totalWidth = totalHours * _hourWidth + 80;
    final mainAreaHeight = numRows * _rowHeight;
    const reminderRowHeight = 32.0;

    // Collect all reminder markers
    final reminderMarkers = _buildReminderMarkers(entries, startHour, mainAreaHeight);
    final hasReminders = reminderMarkers.isNotEmpty;
    final totalHeight =
        _timeAxisHeight + mainAreaHeight + (hasReminders ? reminderRowHeight : 0);

    if (entries.isEmpty && blocks.isEmpty) {
      return _buildEmptyTimeline(totalWidth, startHour, endHour, currentTimeX, totalHeight);
    }

    return SizedBox(
      width: totalWidth,
      height: totalHeight,
      child: Stack(
        children: [
          _buildTimeAxis(startHour, endHour, totalWidth),
          ...blocks.map((b) => _buildBlockBackground(b, startHour, mainAreaHeight)),
          ...rows.asMap().entries.expand((e) =>
              e.value.map((entry) => _buildSessionRect(entry, e.key, startHour))),
          if (hasReminders) ...reminderMarkers,
          if (currentTimeX != null &&
              currentTimeX >= 0 &&
              currentTimeX <= totalWidth)
            _buildCurrentTimeLine(currentTimeX, totalHeight),
          // Floating revealed timestamps in the time axis area
          for (final rv in _revealedTimestamps.values)
            Positioned(
              left: (rv.x - 18).clamp(0, totalWidth - 40),
              top: 2,
              child: _RevealedTimestampLabel(label: rv.label),
            ),
          // Tapping empty space opens task creation
          Positioned(
            top: _timeAxisHeight,
            left: 0,
            right: 0,
            height: mainAreaHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => TaskSheet.showCreate(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTimeline(double totalWidth, int startHour, int endHour,
      double? currentTimeX, double totalHeight) {
    return SizedBox(
      width: totalWidth,
      height: totalHeight,
      child: Stack(
        children: [
          _buildTimeAxis(startHour, endHour, totalWidth),
          if (currentTimeX != null)
            _buildCurrentTimeLine(currentTimeX, totalHeight),
          Positioned(
            top: _timeAxisHeight + 20,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'No sessions scheduled · tap + to add',
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTimeLine(double x, double totalHeight) {
    return Positioned(
      left: x,
      top: 0,
      bottom: 0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: _timeAxisHeight - 5,
            left: -4,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: AppColors.accentCoral, shape: BoxShape.circle),
            ),
          ),
          Container(
              width: 1.5, height: totalHeight, color: AppColors.accentCoral.withValues(alpha: 0.7)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Time axis
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTimeAxis(int startHour, int endHour, double totalWidth) {
    return Positioned(
      top: 0,
      left: 0,
      width: totalWidth,
      height: _timeAxisHeight,
      child: Stack(
        children: [
          // Background strip
          Container(
            height: _timeAxisHeight,
            color: AppColors.bgPrimary,
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
                height: 1,
                color: AppColors.border),
          ),
          // Hourly tick labels
          for (int h = startHour; h <= endHour; h++)
            Positioned(
              left: (h - startHour) * _hourWidth - 16,
              top: 10,
              child: Text(
                '${h.toString().padLeft(2, '0')}:00',
                style: GoogleFonts.robotoMono(
                    fontSize: 10, color: AppColors.textMuted),
              ),
            ),
          // Vertical tick marks at each hour
          for (int h = startHour; h <= endHour; h++)
            Positioned(
              left: (h - startHour) * _hourWidth,
              bottom: 0,
              child: Container(
                  width: 1,
                  height: 6,
                  color: AppColors.border),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session block rendering
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBlockBackground(
      FixedBlock block, int startHour, double mainAreaHeight) {
    final startParts = block.startTime.split(':');
    final endParts = block.endTime.split(':');
    final startH = int.tryParse(startParts[0]) ?? 0;
    final startM = int.tryParse(startParts[1]) ?? 0;
    final endH = int.tryParse(endParts[0]) ?? 0;
    final endM = int.tryParse(endParts[1]) ?? 0;

    final startX = (startH - startHour) * _hourWidth + (startM / 60.0) * _hourWidth;
    final endX = (endH - startHour) * _hourWidth + (endM / 60.0) * _hourWidth;
    final width = endX - startX;
    if (width <= 0) return const SizedBox.shrink();

    return Positioned(
      left: startX,
      top: _timeAxisHeight,
      width: width,
      height: mainAreaHeight,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.border.withValues(alpha: 0.12),
          border: Border(
            left: BorderSide(color: AppColors.border.withValues(alpha: 0.35)),
            right: BorderSide(color: AppColors.border.withValues(alpha: 0.35)),
          ),
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(block.title,
                style: GoogleFonts.inter(
                    fontSize: 9, color: AppColors.textSecondary)),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionRect(_SessionEntry entry, int rowIdx, int startHour) {
    final task = entry.task;
    final session = entry.session;
    // Only timed sessions make it here (sessionsOnDay already filters)
    if (session.startTime == null) return const SizedBox.shrink();
    final startX = (session.startTime!.hour - startHour) * _hourWidth +
        (session.startTime!.minute / 60.0) * _hourWidth;

    double width;
    double? endX;
    if (session.endTime != null) {
      endX = (session.endTime!.hour - startHour) * _hourWidth +
          (session.endTime!.minute / 60.0) * _hourWidth;
      width = (endX - startX).clamp(_minTaskWidth, double.infinity);
    } else if (session.durationMinutes != null) {
      width = (session.durationMinutes! / 60.0) * _hourWidth;
      width = width.clamp(_minTaskWidth, double.infinity);
    } else {
      width = _hourWidth;
    }

    final top = _timeAxisHeight + rowIdx * _rowHeight;
    final isComplete = task.status == 'complete';
    final catColor = AppColors.categoryColor(task.category);
    final catBg = AppColors.categoryBg(task.category);
    final isOverdue = task.isOverdue;

    // Keys for tap-to-reveal
    final startKey = '${session.id}_start';
    final endKey = '${session.id}_end';

    return Positioned(
      left: startX,
      top: top,
      child: GestureDetector(
        onTap: () => TaskSheet.showEdit(context, task),
        onDoubleTap: () => _showTitlePopup(context, task.title),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Start dotted line — tappable to reveal HH:MM
            Positioned(
              left: 0,
              top: -_timeAxisHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _revealTimestamp(startKey, startX, session.startTime!),
                child: SizedBox(
                  width: 20,
                  height: _timeAxisHeight,
                  child: Center(
                    child: _DottedLine(
                      height: _timeAxisHeight,
                      color: catColor.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            // End dotted line — tappable to reveal HH:MM
            if (endX != null)
              Positioned(
                left: width - 10,
                top: -_timeAxisHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _revealTimestamp(endKey, endX!, session.endTime!),
                  child: SizedBox(
                    width: 20,
                    height: _timeAxisHeight,
                    child: Center(
                      child: _DottedLine(
                        height: _timeAxisHeight,
                        color: catColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
            // Task block
            Container(
              width: width,
              height: _rowHeight - 8,
              margin: const EdgeInsets.only(top: 4, bottom: 4),
              decoration: BoxDecoration(
                color: isComplete
                    ? AppColors.success.withValues(alpha: 0.10)
                    : isOverdue
                        ? AppColors.danger.withValues(alpha: 0.08)
                        : catBg,
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(
                    color: isComplete
                        ? AppColors.success
                        : isOverdue
                            ? AppColors.danger
                            : catColor,
                    width: 3,
                  ),
                ),
                boxShadow: AppColors.subtleShadow,
              ),
              padding: const EdgeInsets.only(left: 10, right: 8, top: 5, bottom: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.title,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isComplete
                          ? AppColors.success
                          : isOverdue
                              ? AppColors.danger
                              : AppColors.textPrimary,
                      decoration: isComplete
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (session.endTime != null || session.durationMinutes != null)
                    Text(
                      session.label,
                      style: GoogleFonts.inter(
                          fontSize: 9, color: AppColors.textSecondary),
                      maxLines: 1,
                    ),
                ],
              ),
            ),
            // Reminder count badge on session block (top-right)
            if (session.reminders.isNotEmpty)
              Positioned(
                right: 4,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.45)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.notifications_rounded,
                        size: 8, color: AppColors.warning),
                    const SizedBox(width: 2),
                    Text('${session.reminders.length}',
                        style: GoogleFonts.inter(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Layout: arrange sessions into non-overlapping rows
  // ─────────────────────────────────────────────────────────────────────────

  List<List<_SessionEntry>> _layoutIntoRows(List<_SessionEntry> entries) {
    if (entries.isEmpty) return [];
    final sorted = [...entries]
      ..sort((a, b) {
        final as = a.session.startTime;
        final bs = b.session.startTime;
        if (as == null && bs == null) return 0;
        if (as == null) return 1;
        if (bs == null) return -1;
        return as.compareTo(bs);
      });
    final rows = <List<_SessionEntry>>[];
    for (final entry in sorted) {
      bool placed = false;
      for (final row in rows) {
        final last = row.last;
        final lastEnd = last.session.endTime ??
            (last.session.startTime?.add(const Duration(hours: 1)) ?? DateTime.now());
        final entryStart = entry.session.startTime ?? DateTime.now();
        if (entryStart.isAfter(lastEnd) || entryStart == lastEnd) {
          row.add(entry);
          placed = true;
          break;
        }
      }
      if (!placed) rows.add([entry]);
    }
    return rows;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reminder markers — diamond shapes above sessions
  // ─────────────────────────────────────────────────────────────────────────

  List<Widget> _buildReminderMarkers(
      List<_SessionEntry> entries, int startHour, double mainAreaHeight) {
    final markers = <Widget>[];
    for (final entry in entries) {
      final task = entry.task;
      final session = entry.session;
      if (session.startTime == null) continue;

      for (final reminder in session.reminders) {
        // before_deadline doesn't make geometric sense on a session — skip it
        if (reminder.triggerMode == 'before_deadline') continue;

        final offset = Duration(minutes: reminder.offsetMinutes ?? 0);
        DateTime? fireAt;
        switch (reminder.triggerMode) {
          case 'before_start':
            fireAt = session.startTime!.subtract(offset);
            break;
          case 'after_start':
            fireAt = session.startTime!.add(offset);
            break;
          case 'before_end':
            if (session.endTime != null) {
              fireAt = session.endTime!.subtract(offset);
            }
            break;
          case 'absolute':
            fireAt = reminder.absoluteTime;
            break;
        }
        if (fireAt == null) continue;
        if (!_isSameDay(fireAt, _selectedDay)) continue;

        final rx = (fireAt.hour - startHour) * _hourWidth +
            (fireAt.minute / 60.0) * _hourWidth;
        if (rx < 0) continue;

        markers.add(_buildReminderMarker(
            rx, fireAt, task, reminder, mainAreaHeight));
      }
    }
    return markers;
  }

  /// Reminder markers look DELIBERATELY different from session blocks:
  /// - Session blocks: tall rounded rectangles, category-colored fill + left border
  /// - Reminder markers: small rotated diamond (square rotated 45°), below the
  ///   timeline rows, color-coded by alert type, with a connecting dashed stem
  Widget _buildReminderMarker(double rx, DateTime fireAt, Task task,
      TaskReminder reminder, double mainAreaHeight) {
    // Color by most prominent alert type
    final Color color;
    if (reminder.alertTypes.contains('alarm')) {
      color = AppColors.danger;
    } else if (reminder.alertTypes.contains('callout')) {
      color = AppColors.info;
    } else if (reminder.alertTypes.contains('ringtone')) {
      color = AppColors.warning;
    } else {
      color = AppColors.textMuted;
    }

    // Position: below main rows area, vertically separated from session blocks
    const double stemHeight = 8;
    const double diamondSize = 11;
    const double totalHeight = stemHeight + diamondSize;
    final double topOffset = _timeAxisHeight + mainAreaHeight + 2;

    return Positioned(
      left: rx - diamondSize / 2,
      top: topOffset,
      child: GestureDetector(
        onTap: () => TaskSheet.showEdit(context, task),
        child: Tooltip(
          message:
              '${task.title}\n${reminder.triggerLabel()}',
          child: SizedBox(
            width: diamondSize,
            height: totalHeight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dashed stem connecting to timeline
                SizedBox(
                  height: stemHeight,
                  child: CustomPaint(
                    painter: _DashedLinePainter(color: color),
                  ),
                ),
                // Diamond shape — clearly NOT a session block
                Transform.rotate(
                  angle: 0.7854, // 45°
                  child: Container(
                    width: diamondSize * 0.78,
                    height: diamondSize * 0.78,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      border: Border.all(color: color, width: 1.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Flexible / unscheduled section
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSectionDivider(String label, {int? count}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        if (count != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.accentPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: GoogleFonts.inter(
                    fontSize: 10, color: AppColors.accentPrimary)),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
            child: Container(
                height: 1,
                color: AppColors.border.withValues(alpha: 0.5))),
      ]),
    );
  }

  Widget _buildFlexChip(Task task) {
    final isDone = task.status == 'complete';
    final isOverdue = task.isOverdue;
    final color = isOverdue
        ? AppColors.danger
        : isDone
            ? AppColors.success
            : _categoryColor(task.category);

    return GestureDetector(
      onTap: () => TaskSheet.showEdit(context, task),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppColors.subtleShadow,
          border: Border(
            left: BorderSide(
              color: isOverdue
                  ? AppColors.danger
                  : isDone
                      ? AppColors.success
                      : _categoryColor(task.category),
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              color: color,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDone ? AppColors.textSecondary : AppColors.textPrimary,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (task.deadline != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Due ${_fmtDeadline(task.deadline!)}',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: isOverdue ? AppColors.danger : AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Reminder count
            if (task.reminders.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.notifications_outlined,
                    size: 12,
                    color: task.reminders.isNotEmpty
                        ? AppColors.warning
                        : AppColors.textMuted),
                const SizedBox(width: 2),
                Text('${task.reminders.length}',
                    style: GoogleFonts.inter(
                        fontSize: 10, color: AppColors.warning)),
                const SizedBox(width: 8),
              ]),
            // Category badge
            if (task.category != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _categoryColor(task.category).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(task.category!,
                    style: GoogleFonts.inter(
                        fontSize: 9,
                        color: _categoryColor(task.category))),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dialogs
  // ─────────────────────────────────────────────────────────────────────────

  void _showTitlePopup(BuildContext context, String title) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.bgElevated,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(title,
              style: GoogleFonts.inter(
                  fontSize: 15, color: AppColors.textPrimary)),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Colour per category
  // ─────────────────────────────────────────────────────────────────────────

  Color _categoryColor(String? category) =>
      AppColors.categoryColor(category);

  // ─────────────────────────────────────────────────────────────────────────
  // Utility
  // ─────────────────────────────────────────────────────────────────────────

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _blockAppliesToDay(FixedBlock block, DateTime day) {
    const dayNames = [
      'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
    ];
    return block.days.contains(dayNames[day.weekday - 1]);
  }

  String _dateStr(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _fullDateStr(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _fmtDeadline(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.isNegative) return 'overdue';
    if (diff.inHours < 24) return 'in ${diff.inHours}h';
    return '${dt.day}/${dt.month}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dotted vertical line widget
// ─────────────────────────────────────────────────────────────────────────────

class _DottedLine extends StatelessWidget {
  final double height;
  final Color? color;
  const _DottedLine({required this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: height,
      child: CustomPaint(painter: _DottedLinePainter(color: color)),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  final Color? color;
  const _DottedLinePainter({this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color ?? AppColors.border
      ..strokeWidth = 1.5;
    const dashH = 4.0;
    const gapH = 3.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dashH), paint);
      y += dashH + gapH;
    }
  }

  @override
  bool shouldRepaint(_DottedLinePainter old) => old.color != color;
}

/// Dashed vertical line — used as the stem connecting a reminder diamond to the
/// timeline. Shorter dashes than _DottedLinePainter to look distinct.
class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..strokeWidth = 1.2;
    const dashH = 2.5;
    const gapH  = 2.0;
    double y = 0;
    final cx = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(Offset(cx, y), Offset(cx, (y + dashH).clamp(0, size.height)), paint);
      y += dashH + gapH;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating revealed timestamp label (auto-fading)
// ─────────────────────────────────────────────────────────────────────────────

class _RevealedTimestampLabel extends StatefulWidget {
  final String label;
  const _RevealedTimestampLabel({required this.label});

  @override
  State<_RevealedTimestampLabel> createState() => _RevealedTimestampLabelState();
}

class _RevealedTimestampLabelState extends State<_RevealedTimestampLabel>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 2000),
        () => mounted ? _ctrl.reverse() : null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.accentPrimary,
          borderRadius: BorderRadius.circular(6),
          boxShadow: AppColors.accentShadow,
        ),
        child: Text(
          widget.label,
          style: GoogleFonts.robotoMono(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
