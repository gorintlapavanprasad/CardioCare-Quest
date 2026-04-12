import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../../core/theme/app_colors.dart';
import 'auth_screen.dart'; // Points to your survey flow
import '../dashboard/screens/home_tab.dart';    // Points to your dashboard
import 'auth_provider.dart';

class ChoiceScreen extends StatelessWidget {
  const ChoiceScreen({super.key});

  /// Path A: The "Login" Logic (Direct to Dashboard)
  /// This bypasses authentication by using the phone's model as a unique ID.
  Future<void> _handleQuickLogin(BuildContext context) async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String deviceId = "Visitor";

    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        // Example: Demo_Pixel_8_1711723456
        deviceId = "Demo_${androidInfo.model}_${DateTime.now().millisecondsSinceEpoch.toString().substring(10)}";
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceId = "Demo_${iosInfo.utsname.machine}_${DateTime.now().millisecondsSinceEpoch.toString().substring(10)}";
      }
    } catch (e) {
      deviceId = "Guest_${DateTime.now().millisecond}";
    }

    // Set the global Participant ID so the Dashboard knows where to save game data.
    if (context.mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.updateField('participant_id', deviceId);

      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (context) => const HomeTab())
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Thematic Header
              Icon(Icons.favorite_rounded, size: 80, color: AppColors.viridis2),
              const SizedBox(height: 24),
              Text(
                "How would you like to start?", 
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 12),
              const Text(
                "Choose a path to enter the Cardio Care experience.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.placeholder),
              ),
              const SizedBox(height: 48),
              
              // PATH 1: QUICK DEMO (Visitor)
              _choiceButton(
                context,
                title: "Quick Demo (Visitor)",
                subtitle: "Jump straight to the dashboard",
                icon: Icons.bolt_rounded,
                color: AppColors.viridis4, // Yellow/Green
                onTap: () => _handleQuickLogin(context),
              ),
              
              const SizedBox(height: 20),
              
              // PATH 2: JOIN STUDY (Full Setup)
              _choiceButton(
                context,
                title: "Join Study (Full Setup)",
                subtitle: "Complete the health survey",
                icon: Icons.assignment_ind_rounded,
                color: AppColors.viridis2, // Teal
                onTap: () {
                  Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (context) => const AuthScreen())
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choiceButton(BuildContext context, {
    required String title, 
    required String subtitle, 
    required IconData icon, 
    required Color color,
    required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title, 
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.title)
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle, 
                    style: const TextStyle(color: AppColors.subtitle, fontSize: 13)
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}