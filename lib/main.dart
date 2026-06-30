import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/storage_service.dart';
import 'services/auth_service.dart';
import 'services/gemini_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/sync_service.dart';
import 'package:alarm/alarm.dart';
import 'screens/reminder_alert_screen.dart';
import 'dart:async';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: 'assets/.env');
  } catch (e) {
    debugPrint(
        'Warning: Could not load .env file. Chatbot will run in offline mode.');
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized.');
  } catch (e) {
    debugPrint('Firebase initialization failed — $e');
  }

  final storageService = StorageService();
  await storageService.init();

  final notificationService = NotificationService();
  final backgroundService = SystemBackgroundService();
  if (!kIsWeb) {
    await notificationService.init();
    await backgroundService.init();
  }

  final authService = AuthService(storageService);
  final geminiService = GeminiService(storageService, notificationService);
  final syncService = SyncService(storageService);
  syncService.init();

  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: storageService),
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider<GeminiService>.value(value: geminiService),
        ChangeNotifierProvider<NotificationService>.value(
            value: notificationService),
        ChangeNotifierProvider<SyncService>.value(value: syncService),
      ],
      child: PlanMateApp(showOnboarding: !onboardingDone),
    ),
  );
}

class PlanMateApp extends StatefulWidget {
  final bool showOnboarding;
  const PlanMateApp({super.key, required this.showOnboarding});

  @override
  State<PlanMateApp> createState() => _PlanMateAppState();
}

class _PlanMateAppState extends State<PlanMateApp> {
  StreamSubscription<AlarmSettings>? _ringSubscription;
  void _handleRingingAlarm(AlarmSettings alarmSettings) {
    // If the audio loops (Alarms and Ringtones), we MUST show the UI 
    // so the user has a way to stop it. Standard one-off notifications can be ignored.
    if (!alarmSettings.loopAudio) return;
    
    final handledAlarms = NotificationService().handledAlarmIds;
    if (handledAlarms.contains(alarmSettings.id)) return;
    
    handledAlarms.add(alarmSettings.id);

    // Defer navigation until after the current frame to guarantee the 
    // MaterialApp's Navigator is fully mounted, fixing cold-start races.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav != null) {
        nav.push(
          MaterialPageRoute(
            builder: (context) => ReminderAlertScreen(alarmSettings: alarmSettings),
          ),
        ).then((_) {
          // When screen is dismissed (e.g., via Stop button), remove it from set
          handledAlarms.remove(alarmSettings.id);
        });
      } else {
        // If Navigator is still null, we failed to show the UI.
        // Clear the ID so we don't get permanently stuck, and log the failure.
        debugPrint('CRITICAL ERROR: Navigator was null in addPostFrameCallback. Failed to push ReminderAlertScreen for alarm ${alarmSettings.id}.');
        handledAlarms.remove(alarmSettings.id);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // 1. Listen for alarms ringing while the app is alive.
    _ringSubscription = Alarm.ringStream.stream.listen(_handleRingingAlarm);
    
    // 2. Explicitly check for currently ringing alarms to handle cold-start gaps.
    // If the stream fired before this widget mounted (and doesn't replay),
    // this check guarantees we catch it and show the UI.
    _checkColdStartAlarms();
  }

  Future<void> _checkColdStartAlarms() async {
    try {
      final alarms = Alarm.getAlarms();
      for (final alarm in alarms) {
        if (alarm.loopAudio && await Alarm.isRinging(alarm.id)) {
          _handleRingingAlarm(alarm);
          break; // Show one at a time
        }
      }
    } catch (e) {
      debugPrint('Error checking cold start alarms: $e');
    }
  }

  @override
  void dispose() {
    _ringSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'planMate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: widget.showOnboarding ? const OnboardingScreen() : const AppShell(),
    );
  }
}
