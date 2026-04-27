import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart'; // ─── ADDED: Required for Netgauge Logging

import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';

// ─── CARDIO CARE IMPORTS ───
import 'features/auth/auth_provider.dart';

// ─── NETGAUGE ENGINE IMPORTS ───
import 'package:cardio_care_quest/core/providers/user_data_manager.dart'; // The Netgauge Brain
import 'package:cardio_care_quest/core/services/activity_logs.dart';    // The Netgauge Telemetry Logger

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2. Initialize Netgauge Logging Service (From original Netgauge architecture)
  final getIt = GetIt.instance;
  final loggingService = LoggingService();
  await loggingService.init();
  getIt.registerSingleton<LoggingService>(loggingService);

  runApp(
    // 3. MultiProvider ensures both brains are available to all screens
    MultiProvider(
      providers: [
        // Your Cardio Care onboarding/auth state
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        
        // The Netgauge Brain (Telemetry, XP, Firebase sync)
        ChangeNotifierProvider(create: (_) => UserDataProvider()),
      ],
      child: const CardioCareQuest(),
    ),
  );
}

class CardioCareQuest extends StatelessWidget {
  const CardioCareQuest({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cardio Care Quest',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
