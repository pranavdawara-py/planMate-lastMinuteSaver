import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../screens/dashboard_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/timeline_screen.dart';
import '../screens/history_screen.dart';
import '../screens/settings_screen.dart';
import '../services/gemini_service.dart';
import '../services/storage_service.dart';
import '../widgets/task_detail_bottom_sheet.dart';
import 'chatbot_panel.dart';
import 'account_panel.dart';

final appShellKey = GlobalKey<AppShellState>();

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isChatOpen = false;

  static const _tabNames = [
    'dashboard', 'tasks', 'timeline', 'history', 'settings'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gemini = context.read<GeminiService>();
      final storage = context.read<StorageService>();
      gemini.onNavigate = _navigateToScreen;
      gemini.onOpenTaskDetail = (taskId) {
        final task = storage
            .getTasks()
            .where((t) => t.id == taskId)
            .firstOrNull;
        if (task != null && mounted) {
          TaskDetailBottomSheet.show(context, task);
        }
      };
    });
  }

  void _navigateToScreen(String screenName) {
    final idx = _tabNames.indexOf(screenName);
    if (idx >= 0) _tabController.animateTo(idx);
  }

  void switchTab(int index) => _tabController.animateTo(index);
  void openChat() => setState(() => _isChatOpen = true);
  void closeChat() => setState(() => _isChatOpen = false);
  void toggleChat() => setState(() => _isChatOpen = !_isChatOpen);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: appShellKey,
      backgroundColor: AppColors.bgPrimary,
      endDrawer: const AccountPanel(),
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              DashboardScreen(),
              TasksScreen(),
              TimelineScreen(),
              HistoryScreen(),
              SettingsScreen(),
            ],
          ),
          ChatbotPanel(
            isOpen: _isChatOpen,
            onClose: closeChat,
          ),
          _buildChatToggleTab(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.bgPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: AppColors.border,
      titleSpacing: 16,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.alarm_on,
                color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          Text(
            'planMate',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 19,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
      actions: [
        Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.cloud_outlined,
                color: AppColors.accentPrimary),
            tooltip: 'Sessions & Account',
            onPressed: () => Scaffold.of(ctx).openEndDrawer(),
          ),
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(42),
        child: _buildTabBar(),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AppColors.border.withValues(alpha: 0.5), width: 1),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        indicatorColor: AppColors.accentPrimary,
        indicatorWeight: 2,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: AppColors.accentPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 12),
        tabs: const [
          Tab(text: 'Dashboard'),
          Tab(text: 'Tasks'),
          Tab(text: 'Timeline'),
          Tab(text: 'History'),
          Tab(icon: Icon(Icons.settings_outlined, size: 18)),
        ],
      ),
    );
  }

  Widget _buildChatToggleTab() {
    return Positioned(
      right: _isChatOpen ? null : 0,
      left: _isChatOpen ? 0 : null,
      top: 0,
      bottom: 0,
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: toggleChat,
          child: Container(
            width: 24,
            height: 68,
            decoration: BoxDecoration(
              gradient: _isChatOpen
                  ? null
                  : AppColors.accentGradientVertical,
              color: _isChatOpen ? AppColors.border : null,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(8),
                bottomLeft: const Radius.circular(8),
                topRight: _isChatOpen
                    ? const Radius.circular(8)
                    : Radius.zero,
                bottomRight: _isChatOpen
                    ? const Radius.circular(8)
                    : Radius.zero,
              ),
              boxShadow: _isChatOpen
                  ? null
                  : [
                      BoxShadow(
                        color: AppColors.accentGlow,
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
            ),
            child: Icon(
              _isChatOpen
                  ? Icons.chevron_right
                  : Icons.forum_outlined,
              color: _isChatOpen
                  ? AppColors.textSecondary
                  : Colors.white,
              size: 15,
            ),
          ),
        ),
      ),
    );
  }
}
