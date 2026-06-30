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

class PlanMateApp extends StatelessWidget {
  final bool showOnboarding;
  const PlanMateApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'planMate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: showOnboarding ? const OnboardingScreen() : const AppShell(),
    );
  }
}
