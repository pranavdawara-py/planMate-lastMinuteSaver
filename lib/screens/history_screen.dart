import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../models/task.dart';
import '../services/storage_service.dart';
import '../widgets/task_detail_bottom_sheet.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  bool _scrolledToBottom = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToTop() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<StorageService>(
      builder: (context, storage, _) {
        var tasks = storage
            .getTasks()
            .where((t) => t.status == 'complete')
            .toList();

        // Sort oldest → newest (by completedAt)
        tasks.sort((a, b) {
          final aT = a.completedAt;
          final bT = b.completedAt;
          if (aT == null && bT == null) return 0;
          if (aT == null) return -1;
          if (bT == null) return 1;
          return aT.compareTo(bT);
        });

        // Filter by search
        if (_search.isNotEmpty) {
          tasks = tasks
              .where((t) => t.title.toLowerCase().contains(_search.toLowerCase()))
              .toList();
        }

        // Group by completedAt date
        final grouped = <DateTime, List<Task>>{};
        for (final t in tasks) {
          final dt = t.completedAt;
          final key = dt != null
              ? DateTime(dt.year, dt.month, dt.day)
              : DateTime(1970); // fallback for tasks with no completedAt
          grouped.putIfAbsent(key, () => []).add(t);
        }
        final sortedDates = grouped.keys.toList()..sort();

        // Build flat list of headers + tasks
        final List<dynamic> flatList = [];
        for (final date in sortedDates) {
          flatList.add(date); // header
          flatList.addAll(grouped[date]!); // tasks
        }

        // Auto-scroll to bottom on first load
        if (!_scrolledToBottom && tasks.isNotEmpty) {
          _scrolledToBottom = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollCtrl.hasClients) {
              _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
            }
          });
        }

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          body: Column(
            children: [
              _buildSearchBar(),
              Expanded(
                child: tasks.isEmpty
                    ? _buildEmpty()
                    : Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                            itemCount: flatList.length,
                            itemBuilder: (context, i) {
                              final item = flatList[i];
                              if (item is DateTime) {
                                return _buildDateHeader(item);
                              }
                              return _buildHistoryTile(item as Task);
                            },
                          ),
                          // Jump buttons
                          Positioned(
                            bottom: 16,
                            right: 16,
                            child: Column(
                              children: [
                                _JumpButton(
                                  icon: Icons.keyboard_double_arrow_up,
                                  tooltip: 'Jump to oldest',
                                  onTap: _scrollToTop,
                                ),
                                const SizedBox(height: 8),
                                _JumpButton(
                                  icon: Icons.keyboard_double_arrow_down,
                                  tooltip: 'Jump to newest',
                                  onTap: _scrollToBottom,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: AppColors.bgPrimary,
      child: Container(
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
            hintText: 'Search history...',
            hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
            prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 18),
            suffixIcon: _search.isNotEmpty
                ? GestureDetector(
                    onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                    child: const Icon(Icons.close, color: AppColors.textSecondary, size: 16))
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final epoch = DateTime(1970);
    String label;
    if (date == epoch) {
      label = 'Earlier';
    } else if (date == today) {
      label = 'Today';
    } else if (date == yesterday) {
      label = 'Yesterday';
    } else {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      label = '${date.day} ${months[date.month - 1]} ${date.year}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Row(children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.accentPrimary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(height: 1, color: AppColors.border.withValues(alpha: 0.4)),
        ),
      ]),
    );
  }

  Widget _buildHistoryTile(Task t) {
    return GestureDetector(
      onTap: () => TaskDetailBottomSheet.show(context, t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: AppColors.success, size: 15),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (t.completedAt != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Completed ${_completedLabel(t.completedAt!)}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (t.category != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.categoryBg(t.category),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(t.category!,
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppColors.categoryColor(t.category))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📖', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No completed tasks yet',
              style: GoogleFonts.inter(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Completed tasks will appear here.',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  String _completedLabel(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _JumpButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _JumpButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 18),
        ),
      ),
    );
  }
}
