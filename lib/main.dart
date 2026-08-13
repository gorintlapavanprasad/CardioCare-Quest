// App entry point. Sets up Firebase, the offline queue, providers, and
// text scaling before showing the first screen.

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart'; // ─── ADDED: Required for Netgauge Logging

import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/hooks/pair_hooks.dart';
import 'core/services/session_manager.dart';
import 'core/services/session_settings_service.dart';
import 'core/services/pair_resume_service.dart';
import 'features/splash/splash_screen.dart';

// ─── CARDIO CARE IMPORTS ───
import 'features/auth/auth_provider.dart';

// ─── NETGAUGE ENGINE IMPORTS ───
import 'package:cardio_care_quest/core/providers/user_data_manager.dart'; // The Netgauge Brain
import 'package:cardio_care_quest/core/services/activity_logs.dart';    // The Netgauge Telemetry Logger
import 'package:cardio_care_quest/core/services/offline_queue.dart';    // Generic offline write queue

// Sets up services, then shows the UI.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 1b. Set Firestore cache to unlimited so long offline sessions never lose
  // pending writes. Persistence is on by default; we set it explicitly anyway.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // 2. Start the logging service.
  final getIt = GetIt.instance;
  final loggingService = LoggingService();
  await loggingService.init();
  getIt.registerSingleton<LoggingService>(loggingService);

  // 2b. Start the offline queue for BP, meals, surveys, and other writes.
  final offlineQueue = OfflineQueue();
  await offlineQueue.init();
  getIt.registerSingleton<OfflineQueue>(offlineQueue);

  // 3. Run the app; MultiProvider makes shared state available everywhere.
  runApp(
    MultiProvider(
      providers: [
        // Auth/onboarding state.
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // Points, telemetry, and Firebase sync.
        ChangeNotifierProvider(create: (_) => UserDataProvider()),
      ],
      child: const CardioCareQuest(),
    ),
  );
}

// Root widget. Watches app lifecycle to pause/resume a paired session.
class CardioCareQuest extends StatefulWidget {
  const CardioCareQuest({super.key});

  @override
  State<CardioCareQuest> createState() => _CardioCareQuestState();
}

class _CardioCareQuestState extends State<CardioCareQuest>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Reattach a paired session left over from a previous run.
    PairResumeService.instance.tryRestore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Pause/resume the paired session heartbeat as the app goes in/out of focus.
  // No-ops when no session is active.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!SessionManager.isPaired) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      PairHooks.pause();
    } else if (state == AppLifecycleState.resumed) {
      PairHooks.resume();
    }
  }

  // App shell: theme, global text scale (set by joint setup), first screen.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cardio Care Quest',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // textScaler multiplies every Text widget; defaults to 1.0 until
      // a paired session picks a larger size.
      builder: (context, child) {
        return ValueListenableBuilder<SessionSettings>(
          valueListenable: SessionSettingsService.instance.settings,
          builder: (context, s, _) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(s.textScale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
      home: const SplashScreen(),
    );
  }
}
