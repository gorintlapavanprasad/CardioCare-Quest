// splash_screen.dart - the first screen you see when the app opens.
//
// It shows the logo, then decides where to send you: to login, or (for a
// returning user) straight past a fingerprint/face unlock into the app.
// Right now it's in "demo mode", so it always just shows a Begin button.

import 'package:cardio_care_quest/features/dashboard/screens/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/firestore_paths.dart';
import '../auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Demo mode: skip the "remember me / unlock" checks and always show the
  // Begin button. Handy for showing the app quickly at a conference.
  final bool _isDemoMode = true;
  final LocalAuthentication _auth = LocalAuthentication(); // fingerprint / face
  final FlutterSecureStorage _storage = const FlutterSecureStorage(); // safe on-phone store

  bool _showButton = false; // is the bottom button visible yet?
  bool _isReturningUser = false; // did we find a saved account on this phone?

  // Pops a small on-screen message and logs it - used while testing.
  void _showDebugAlert(String message) {
    debugPrint("🛠️ DEBUG: $message");
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blueGrey,
        ),
      );
    });
  }

  // Runs once when the splash appears. Kicks off the "where do we go?" logic.
  @override
  void initState() {
    super.initState();
    debugPrint("🛠️ DEBUG: Splash Screen Initialized");
    _initializeApp();
  }

  // Wait a beat for the logo, then decide the next screen.
  Future<void> _initializeApp() async {
    // Shorter delay since we aren't waiting for a long animation
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    // Demo mode: don't bother checking for a saved account, just show Begin.
    if (_isDemoMode) {
      setState(() {
        _isReturningUser = false;
        _showButton = true;
      });
      return;
    }

    // Do we have an account saved on this phone from last time?
    String? savedId = await _storage.read(key: 'participant_id');

    if (savedId != null && mounted) {
      debugPrint("🛠️ DEBUG: Found Local ID: $savedId. Verifying with server...");
      try {
        // Double-check the saved account still exists in the cloud.
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection(FirestorePaths.userData).doc(savedId).get();
        if (userDoc.exists && mounted) {
          debugPrint("🛠️ DEBUG: Server Verified! Triggering Biometrics.");
          setState(() => _isReturningUser = true);
          _triggerBiometricLogin();
        } else if (mounted) {
          debugPrint("🛠️ DEBUG: ID not found on server. Wiping local data.");
          await _storage.delete(key: 'participant_id');
          setState(() {
            _isReturningUser = false;
            _showButton = true;
          });
        }
      } catch (e) {
        // No internet? Trust the saved account and let them unlock anyway.
        debugPrint("🛠️ DEBUG: Network error. Defaulting to local biometric cache: $e");
        setState(() => _isReturningUser = true);
        _triggerBiometricLogin();
      }
    } else if (mounted) {
      debugPrint("🛠️ DEBUG: No Local ID found -> Showing 'Begin Journey'");
      setState(() {
        _isReturningUser = false;
        _showButton = true;
      });
    }
  }

  // Ask for fingerprint/face. If it passes, jump straight into the app.
  Future<void> _triggerBiometricLogin() async {
    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Unlock to access Cardio Care Quest',
      );

      if (didAuthenticate && mounted) {
        _showDebugAlert("Biometrics Success -> Navigating to Dashboard");
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainLayout()),
        );
      } else {
        _showDebugAlert("Biometrics Failed/Canceled");
        if (mounted) setState(() => _showButton = true);
      }
    } catch (e) {
      _showDebugAlert("Biometrics Error: $e");
      if (mounted) setState(() => _showButton = true);
    }
  }

  // The screen itself: logo in the middle, welcome text and button below.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(color: Colors.white), // Assuming a white background works best for the new logo
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Image.asset(
                  'assets/branding/icon.png', // Ensure this path matches your pubspec.yaml
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
              // ─── NEW STATIC LOGO ───
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Image.asset(
                  'assets/branding/ccq.png', // Ensure this path matches your pubspec.yaml
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),

              const Spacer(flex: 1),
              _buildBottomContent(),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  // The welcome line plus the fade-in button. The button text and where it
  // sends you both depend on whether you're a new or returning user.
  Widget _buildBottomContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Removed the duplicate "Cardio Care Quest" text since the logo has it now
          Text(
            'Welcome to Your Health Journey',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.placeholder,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 48),
          
          IgnorePointer(
            ignoring: !_showButton,
            child: AnimatedOpacity(
              opacity: _showButton ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.viridis4,
                  foregroundColor: AppColors.viridis0,
                  minimumSize: const Size(200, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 8,
                  shadowColor: AppColors.viridis4.withValues(alpha: 0.5),
                ),
                onPressed: () {
                  if (_isReturningUser) {
                    _triggerBiometricLogin();
                  } else {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  }
                },
                child: Text(
                  _isDemoMode ? 'BEGIN JOURNEY' : (_isReturningUser ? 'UNLOCK JOURNEY' : 'ENTER'),
                  style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

