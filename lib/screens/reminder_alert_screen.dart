import 'package:flutter/material.dart';
import 'package:alarm/alarm.dart';
import '../theme/app_colors.dart';

class ReminderAlertScreen extends StatefulWidget {
  final AlarmSettings alarmSettings;

  const ReminderAlertScreen({super.key, required this.alarmSettings});

  @override
  State<ReminderAlertScreen> createState() => _ReminderAlertScreenState();
}

class _ReminderAlertScreenState extends State<ReminderAlertScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _stopAlarm() async {
    await Alarm.stop(widget.alarmSettings.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Extract title and body from the notification settings (alarm 3.0.1 API)
    // Add null-safety fallback in case they are null
    final rawTitle = widget.alarmSettings.notificationTitle;
    final title = (rawTitle.isNotEmpty) ? rawTitle.replaceAll(RegExp(r'⏰ |🔔 |🗣️ |📋 '), '') : 'Alarm Ringing';
    final body = widget.alarmSettings.notificationBody;
    
    // Attempt to extract the icon that was passed in the title, fallback to ⏰
    final iconMatch = RegExp(r'⏰|🔔|🗣️|📋').firstMatch(rawTitle);
    final icon = iconMatch != null ? iconMatch.group(0) : '⏰';

    return PopScope(
      canPop: false, // Prevent accidental swipe or back-button dismiss
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F1A), // Deep dark background
        body: Stack(
          children: [
            // Background Gradient Glow
            Positioned(
              top: -100,
              left: -100,
              right: -100,
              child: Container(
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accentPrimary.withValues(alpha: 0.3),
                      const Color(0xFF0F0F1A).withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
            
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(),
                    
                    // Icon with Pulse
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accentPrimary.withValues(alpha: 0.2),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentPrimary.withValues(alpha: 0.4),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Text(
                          icon!, // Safe because it's guaranteed non-null from above
                          style: const TextStyle(fontSize: 64),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // Task Title
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Reminder Body (Details)
                    if (body.isNotEmpty)
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.7), // Fixed from withOpacity
                          height: 1.4,
                        ),
                      ),
                    
                    const Spacer(),
                    
                    // Stop Button
                    GestureDetector(
                      onTap: _stopAlarm,
                      child: Container(
                        width: double.infinity,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: AppColors.accentGradient,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: AppColors.accentShadow,
                        ),
                        child: const Center(
                          child: Text(
                            'Stop',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
