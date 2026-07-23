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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 1b. Explicit Firestore offline persistence.
  // Mobile SDK enables persistence by default; we set it explicitly + bump the
  // cache to unlimited so long offline sessions at the workshop never evict
  // pending writes. cloud_firestore ^6.x applies these settings cross-platform.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // 2. Initialize Netgauge Logging Service (From original Netgauge architecture)
  final getIt = GetIt.instance;
  final loggingService = LoggingService();
  await loggingService.init();
  getIt.registerSingleton<LoggingService>(loggingService);

  // 2b. Initialize the generic OfflineQueue for all research-grade writes
  // (BP, exercise, meal, medication, quest completions, surveys, etc.).
  final offlineQueue = OfflineQueue();
  await offlineQueue.init();
  getIt.registerSingleton<OfflineQueue>(offlineQueue);

  runApp(
    // 3. MultiProvider ensures both brains are available to all screens
    MultiProvider(
      providers: [
        // Your Cardio Care onboarding/auth state
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        
        // The Netgauge Brain (Telemetry, Points, Firebase sync)
        ChangeNotifierProvider(create: (_) => UserDataProvider()),
      ],
      child: const CardioCareQuest(),
    ),
  );
}

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
    // Reattach an in-progress paired session left over from a previous run.
    PairResumeService.instance.tryRestore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep a paired session's heartbeat / status current as the app moves
    // between foreground and background, so it survives leaving the device and
    // returning. No-ops when no session is active.
    if (!SessionManager.isPaired) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      PairHooks.pause();
    } else if (state == AppLifecycleState.resumed) {
      PairHooks.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cardio Care Quest',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Apply the joint-setup text size globally. Because all typography is
      // themed, a textScaler multiplies every Text uniformly — no per-widget
      // changes. Defaults to 1.0 (unchanged) until a paired session picks a
      // larger size, so solo use is unaffected.
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
