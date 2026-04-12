import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart'; // Add this for state management
import 'firebase_options.dart'; // This is the file you just generated
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/auth_provider.dart'; // We will create this next

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Link the app to your specific Firebase project apps
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    // MultiProvider ensures the 14-step data is available to all screens
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
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