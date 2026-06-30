import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../models/task.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../utils/task_completion_util.dart';
import '../widgets/task_detail_bottom_sheet.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _search = '';
  String? _filterStatus; // 'incomplete' | 'complete' | null
  String? _filterCategory;
  bool _autoScrolled = false;

  static const _categories = ['Work', 'Personal', 'College', 'Health', 'Other'];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<StorageService>(
      builder: (context, storage, _) {
        var tasks = storage.getTasks();

        // Filter + search
        if (_search.isNotEmpty) {
          tasks = tasks.where((t) => t.title.toLowerCase().contains(_search.toLowerCase())).toList();
        }
        if (_filterStatus != null) {
          tasks = tasks.where((t) => t.status == _filterStatus).toList();
        }
        if (_filterCategory != null) {
          tasks = tasks.where((t) => t.category == _filterCategory).toList();
        }

        // Sort by first session start or deadline
        tasks.sort((a, b) {
          final aDate = a.firstSessionStart ?? a.deadline;
          final bDate = b.firstSessionStart ?? b.deadline;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return aDate.compareTo(bDate);
        });

        // Group by day (first session start or deadline)
        final grouped = <DateTime, List<Task>>{};
        final noDate = <Task>[];
        for (final t in tasks) {
          final date = t.firstSessionStart ?? t.deadline;
          if (date == null) {
            noDate.add(t);
          } else {
            final d = DateTime(date.year, date.month, date.day);
            grouped.putIfAbsent(d, () => []).add(t);
          }
        }
        final sortedDays = grouped.keys.toList()..sort();

        // Auto-scroll to today section on first open
        if (!_autoScrolled && sortedDays.isNotEmpty) {
          _autoScrolled = true;
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final todayIdx = sortedDays.indexOf(today);
          if (todayIdx >= 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_scrollCtrl.hasClients) return;
              // Estimate scroll offset: ~34px per day header + ~72px per task
              double offset = 0;
              for (int i = 0; i < todayIdx; i++) {
                offset += 34 + (grouped[sortedDays[i]]!.length * 72.0);
              }
              _scrollCtrl.animateTo(
                offset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
              );
            });
          }
        }

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          floatingActionButton: GestureDetector(
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
          ),
          body: Column(
            children: [
              _buildSearchAndFilters(),
              Expanded(
                child: tasks.isEmpty
                    ? _buildEmpty()
                    : ListView(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        children: [
                          ...sortedDays.map((day) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDayDivider(day),
                                  ...grouped[day]!.map((t) => _buildTaskTile(t, storage)),
                                ],
                              )),
                          if (noDate.isNotEmpty) ...[
                            _buildDayDivider(null),
                            ...noDate.map((t) => _buildTaskTile(t, storage)),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      color: AppColors.bgPrimary,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          // Search bar
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            ),
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search tasks...',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 18),
                suffixIcon: _search.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                        child: const Icon(Icons.close, color: AppColors.textSecondary, size: 16),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(label: 'All', selected: _filterStatus == null && _filterCategory == null,
                    onTap: () => setState(() { _filterStatus = null; _filterCategory = null; })),
                const SizedBox(width: 6),
                _FilterChip(label: 'Incomplete', selected: _filterStatus == 'incomplete',
                    onTap: () => setState(() => _filterStatus = _filterStatus == 'incomplete' ? null : 'incomplete')),
                const SizedBox(width: 6),
                _FilterChip(label: 'Complete', selected: _filterStatus == 'complete',
                    onTap: () => setState(() => _filterStatus = _filterStatus == 'complete' ? null : 'complete')),
                const SizedBox(width: 6),
                ..._categories.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _FilterChip(
                        label: cat,
                        selected: _filterCategory == cat,
                        onTap: () => setState(() => _filterCategory = _filterCategory == cat ? null : cat),
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayDivider(DateTime? day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = day != null && day == today;
    final label = day == null
        ? 'No date'
        : isToday
            ? '✦ Today'
            : '${_dayName(day.weekday)}, ${day.day} ${_monthName(day.month)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Row(children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: isToday ? 14 : 12,
            color: isToday ? AppColors.accentPrimary : AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            color: isToday ? AppColors.accentPrimary.withValues(alpha: 0.3) : AppColors.border.withValues(alpha: 0.4),
          ),
        ),
      ]),
    );
  }

  Widget _buildTaskTile(Task t, StorageService storage) {
    final isDone = t.status == 'complete';
    final catColor = isDone ? AppColors.success : AppColors.categoryColor(t.category);
    final catBg = AppColors.categoryBg(t.category);
    return Dismissible(
      key: Key(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 6),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.danger, size: 22),
      ),
      confirmDismiss: (_) async {
        bool confirmed = false;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.bgSecondary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text('Delete Task?',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            content: Text('This cannot be undone.',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
            actions: [
              TextButton(
                onPressed: () { Navigator.pop(context); confirmed = false; },
                child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () { Navigator.pop(context); confirmed = true; },
                child: Text('Delete', style: GoogleFonts.inter(color: Colors.white)),
              ),
            ],
          ),
        );
        return confirmed;
      },
      onDismissed: (_) => storage.deleteTask(t.id),
      child: GestureDetector(
        onTap: () => TaskDetailBottomSheet.show(context, t),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isDone ? AppColors.bgSecondary.withValues(alpha: 0.7) : AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.subtleShadow,
            border: Border(
              left: BorderSide(color: catColor.withValues(alpha: isDone ? 0.4 : 1.0), width: 3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Check circle with category color
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
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? AppColors.success : Colors.transparent,
                      border: Border.all(
                        color: isDone ? AppColors.success : catColor,
                        width: 2,
                      ),
                    ),
                    child: isDone
                        ? const Icon(Icons.check, size: 13, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDone ? AppColors.textSecondary : AppColors.textPrimary,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_buildSubtitle(t).isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          _buildSubtitle(t),
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (t.reminders.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.notifications_outlined, size: 13, color: AppColors.warning),
                    ),
                  if (t.category != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: catBg,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(t.category!,
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: catColor)),
                    ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📋', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No tasks', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Add a task or ask the AI chatbot', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context, StorageService storage) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _QuickAdd(storage: storage),
      ),
    );
  }

  String _buildSubtitle(Task t) {
    // Use sessions if available
    if (t.sessions.isNotEmpty) {
      return t.sessions.first.label;
    }
    if (t.deadline != null) {
      return 'Due ${t.deadline!.day}/${t.deadline!.month}/${t.deadline!.year}';
    }
    return '';
  }

  String _dayName(int w) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1];
  String _monthName(int m) => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m-1];
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentPrimary : AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.accentPrimary : AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Text(label,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500,
                color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}

class _QuickAdd extends StatefulWidget {
  final StorageService storage;
  const _QuickAdd({required this.storage});
  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final _ctrl = TextEditingController();
  String _type = 'flexible';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(8)))),
          Text('Add Task', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border.withValues(alpha: 0.6))),
            child: TextField(controller: _ctrl, autofocus: true,
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(hintText: 'Task title...', hintStyle: GoogleFonts.inter(color: AppColors.textSecondary),
                  border: InputBorder.none, contentPadding: const EdgeInsets.all(14))),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _buildChip('Flexible', _type == 'flexible', () => setState(() => _type = 'flexible')),
            const SizedBox(width: 8),
            _buildChip('Fixed', _type == 'fixed', () => setState(() => _type = 'fixed')),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final t = _ctrl.text.trim();
                if (t.isEmpty) return;
                final nav = Navigator.of(context);
                await widget.storage.saveTask(Task(
                    id: 'task_${DateTime.now().millisecondsSinceEpoch}', title: t, type: _type));
                if (mounted) nav.pop();
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              child: Text('Add Task', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, bool sel, VoidCallback tap) => GestureDetector(
      onTap: tap,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: sel ? AppColors.accentPrimary : AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: sel ? AppColors.accentPrimary : AppColors.border)),
          child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
              color: sel ? Colors.white : AppColors.textSecondary))));
}
