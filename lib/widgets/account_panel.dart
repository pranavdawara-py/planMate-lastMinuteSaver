import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../screens/login_screen.dart';

class AccountPanel extends StatelessWidget {
  const AccountPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.bgSecondary,
      width: 320,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const Divider(color: AppColors.border, height: 1),
            Expanded(child: _buildSessionList(context)),
            const Divider(color: AppColors.border, height: 1),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        final sessionLabel = auth.isLoggedIn
            ? auth.currentEmail ?? 'Logged in'
            : 'Without Account';
        final sessionIcon = auth.isLoggedIn ? Icons.person_outline : Icons.no_accounts_outlined;

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sessions',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(sessionIcon, size: 13, color: AppColors.accentPrimary),
                  const SizedBox(width: 5),
                  Text(
                    'Active: $sessionLabel',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.accentPrimary),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSessionList(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        final profiles = auth.knownProfiles;

        final sessions = <_SessionItem>[
          _SessionItem(
            uid: 'without_account',
            label: 'Without Account',
            subtitle: 'Local only — never synced',
            icon: Icons.phone_android_outlined,
            isActive: !auth.isLoggedIn,
          ),
          ...profiles.map((p) => _SessionItem(
                uid: p.uid,
                label: p.email,
                subtitle: p.isLoggedIn ? '✓ Logged in' : 'Logged out — data cached',
                icon: Icons.cloud_outlined,
                isActive: auth.isLoggedIn && auth.currentUid == p.uid,
              )),
        ];

        if (sessions.isEmpty) {
          return Center(
            child: Text(
              'No sessions yet',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: sessions.length,
          itemBuilder: (context, i) => _buildSessionTile(context, sessions[i], auth),
        );
      },
    );
  }

  Widget _buildSessionTile(BuildContext context, _SessionItem s, AuthService auth) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: s.isActive
            ? AppColors.accentPrimary.withValues(alpha: 0.08)
            : AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: s.isActive
              ? AppColors.accentPrimary.withValues(alpha: 0.3)
              : AppColors.border.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: s.isActive
                ? AppColors.accentPrimary.withValues(alpha: 0.15)
                : AppColors.bgPrimary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(s.icon,
              color: s.isActive ? AppColors.accentPrimary : AppColors.textSecondary,
              size: 18),
        ),
        title: Text(
          s.label,
          style: GoogleFonts.inter(
            fontWeight: s.isActive ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          s.subtitle,
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
        ),
        trailing: s.isActive
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Switch button
                  _SmallButton(
                    icon: Icons.swap_horiz,
                    tooltip: 'Switch to this session',
                    onTap: () {
                      auth.switchToSession(s.uid);
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 6),
                  // Delete button
                  _SmallButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete session data',
                    color: AppColors.danger,
                    onTap: () => _confirmDelete(context, s, auth),
                  ),
                ],
              ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, _SessionItem s, AuthService auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete session?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
        content: Text(
          'This will permanently delete all local data for "${s.label}". '
          'Cloud data (if any) is not affected.',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              auth.deleteSession(s.uid);
            },
            child: Text('Delete', style: GoogleFonts.inter(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!auth.isLoggedIn) ...[
                Text(
                  'Login is optional. Keep using Without Account as long as you like.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                _PanelActionButton(
                  label: 'Login',
                  icon: Icons.login,
                  color: AppColors.accentPrimary,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LoginScreen(isSignup: false)));
                  },
                ),
                const SizedBox(height: 8),
                _PanelActionButton(
                  label: 'Sign Up',
                  icon: Icons.person_add_outlined,
                  color: AppColors.accentSecondary,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LoginScreen(isSignup: true)));
                  },
                ),
                const SizedBox(height: 8),
                _PanelActionButton(
                  label: 'No Internet Mode',
                  icon: Icons.wifi_off_outlined,
                  color: AppColors.warning,
                  onTap: () => _showNoInternetMode(context, auth),
                ),
              ] else ...[
                _PanelActionButton(
                  label: 'Import guest workspace into account',
                  icon: Icons.upload_outlined,
                  color: AppColors.accentPrimary,
                  onTap: () => _mergeGuestData(context, auth),
                ),
                const SizedBox(height: 8),
                Text(
                  'Guest data stays on this device until you delete it with the trash icon.',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                _PanelActionButton(
                  label: 'Logout',
                  icon: Icons.logout,
                  color: AppColors.textSecondary,
                  onTap: () {
                    auth.logout();
                    Navigator.pop(context);
                  },
                ),
              ],
              const SizedBox(height: 12),
              _PanelActionButton(
                label: 'Clear this session on device',
                icon: Icons.delete_sweep_outlined,
                color: AppColors.danger,
                onTap: () => _confirmClearCurrentSession(context, auth),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _mergeGuestData(BuildContext context, AuthService auth) async {
    try {
      final hasGuest = await auth.guestWorkspaceHasData();
      if (!hasGuest) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No guest workspace data to import.')),
          );
        }
        return;
      }
      final count = await auth.mergeGuestDataIntoAccount();
      if (context.mounted) {
        context.read<SyncService>().triggerQueueSync();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported $count item(s) into your account. Guest copy remains on device.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString(), style: const TextStyle(fontSize: 13)), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        );
      }
    }
  }

  void _confirmClearCurrentSession(BuildContext context, AuthService auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear session on this device?',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Deletes all tasks, schedule, and chat history for the active session on this device only. '
          'Cloud data (if logged in) is not affected.',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await auth.clearActiveSessionData();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: const Text('Session cleared on this device.', style: TextStyle(fontSize: 13)), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                );
              }
            },
            child: Text('Clear', style: GoogleFonts.inter(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showNoInternetMode(BuildContext context, AuthService auth) {
    final profiles = auth.knownProfiles;
    if (profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('No cached accounts found on this device.', style: TextStyle(fontSize: 13)), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Select account to use offline',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
          ...profiles.map((p) => ListTile(
                leading: const Icon(Icons.cloud_off, color: AppColors.textSecondary),
                title: Text(p.email, style: GoogleFonts.inter(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                  auth.enterNoInternetMode(p.uid);
                },
              )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SessionItem {
  final String uid;
  final String label;
  final String subtitle;
  final IconData icon;
  final bool isActive;
  _SessionItem({
    required this.uid,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.isActive,
  });
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  const _SmallButton({
    required this.icon,
    required this.tooltip,
    this.color = AppColors.textSecondary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

class _PanelActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _PanelActionButton(
      {required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: color,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
