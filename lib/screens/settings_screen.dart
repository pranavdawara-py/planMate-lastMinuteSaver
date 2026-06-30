import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _syncMode = 'Full Sync';
  bool _notifsEnabled = true;
  String _notifType = 'sound';

  static const _syncOptions = [
    ('Full Sync', 'Always keep all data synchronized offline'),
    ('Recent Sync', 'Sync only the last 30 days of data locally'),
    ('New Only', 'Synchronize newly created entries only'),
    ('No Sync', 'Operations run purely locally on this device'),
  ];

  @override
  Widget build(BuildContext context) {
    final isAccountSession =
        context.watch<StorageService>().currentSessionType == SessionType.account;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // Sync Section — only for logged-in accounts
          if (isAccountSession) ...[
            _buildSectionHeader('Cloud Sync'),
            _buildCard(
              children: _syncOptions.map((opt) {
                final isSelected = _syncMode == opt.$1;
                return InkWell(
                  onTap: () => setState(() => _syncMode = opt.$1),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        // Custom radio indicator — avoids deprecated Radio API
                        GestureDetector(
                          onTap: () => setState(() => _syncMode = opt.$1),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.accentPrimary
                                    : AppColors.textSecondary,
                                width: isSelected ? 6 : 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                opt.$1,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.accentPrimary
                                      : AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                opt.$2,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Notifications Section
          _buildSectionHeader('Notifications & Alerts'),
          if (kIsWeb)
            _buildCard(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.textSecondary, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Notifications are available on the Android app only.',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ])
          else
            _buildCard(children: [
              // Device notifications toggle
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Device Notifications',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        Text('Allow scheduling triggers and reminders',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _notifsEnabled,
                    onChanged: (val) => setState(() => _notifsEnabled = val),
                    activeThumbColor: Colors.white,
                    trackColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColors.accentPrimary;
                      }
                      return AppColors.border;
                    }),
                  ),
                ],
              ),
              if (_notifsEnabled) ...[
                const Divider(color: AppColors.border, height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Default Audio Type',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary)),
                          Text('Applied to new task reminders',
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    DropdownButton<String>(
                      value: _notifType,
                      dropdownColor: AppColors.bgElevated,
                      underline: const SizedBox.shrink(),
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppColors.textPrimary),
                      items: const [
                        DropdownMenuItem(
                            value: 'sound', child: Text('Sound alerts')),
                        DropdownMenuItem(
                            value: 'silent', child: Text('Silent pushes')),
                        DropdownMenuItem(
                            value: 'tts', child: Text('TTS Read aloud')),
                      ],
                      onChanged: (val) =>
                          setState(() => _notifType = val ?? 'sound'),
                    ),
                  ],
                ),
              ],
            ]),
          const SizedBox(height: 20),

          // Privacy Section
          _buildSectionHeader('Privacy & Data'),
          _buildCard(children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.shield_outlined,
                      color: AppColors.success, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your data is stored locally on your device and synced to the cloud only when signed in. Data is encrypted in transit. Guest workspace data is never uploaded. You can delete your data at any time below.',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 16),

            // ── Clear Chat History ────────────────────────────────────────
            InkWell(
              onTap: () => _confirmClearChat(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded,
                        color: AppColors.danger, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Clear Chat History',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.danger)),
                          Text('Remove AI conversation — tasks remain safe',
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.danger, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── Clear All Data ─────────────────────────────────────────────
            InkWell(
              onTap: () => _confirmClearAll(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.delete_forever_rounded,
                        color: AppColors.danger, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Clear All App Data',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.danger)),
                          Text('Wipe all tasks, schedule & chat from this device',
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.danger, size: 16),
                  ],
                ),
              ),
            ),
          ]),

        ],
      ),
    );
  }

  void _confirmClearChat(BuildContext context) {
    final storage = context.read<StorageService>();
    final count = storage.getChatHistory().length;
    _showDestructiveSheet(
      context: context,
      icon: Icons.chat_bubble_outline_rounded,
      title: 'Clear Chat History',
      body: count == 0
          ? 'Chat history is already empty.'
          : 'This will permanently delete $count message${count == 1 ? '' : 's'}. '
              'The AI will start fresh — your tasks and schedule are unaffected.',
      buttonLabel: 'Clear Chat',
      enabled: count > 0,
      onConfirm: () async {
        await storage.clearConversationHistory();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Chat history cleared',
                  style: GoogleFonts.inter(fontSize: 13)),
              backgroundColor: AppColors.bgElevated,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      },
    );
  }

  void _confirmClearAll(BuildContext context) {
    final storage = context.read<StorageService>();
    _showDestructiveSheet(
      context: context,
      icon: Icons.delete_forever_rounded,
      title: 'Clear All App Data',
      body: 'This will permanently wipe ALL tasks, schedule blocks, and chat history '
          'from this device session. This cannot be undone.',
      buttonLabel: 'Delete Everything',
      enabled: true,
      onConfirm: () async {
        await storage.clearCurrentSessionData();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('All data cleared',
                  style: GoogleFonts.inter(fontSize: 13)),
              backgroundColor: AppColors.bgElevated,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      },
    );
  }

  void _showDestructiveSheet({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String body,
    required String buttonLabel,
    required bool enabled,
    required VoidCallback onConfirm,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.danger, size: 18),
                ),
                const SizedBox(width: 12),
                Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 14),
            Text(body,
                style: GoogleFonts.inter(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Cancel', style: GoogleFonts.inter(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: enabled
                        ? () {
                            Navigator.pop(context);
                            onConfirm();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      disabledBackgroundColor: AppColors.border,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: Text(buttonLabel,
                        style: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          color: AppColors.accentPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
