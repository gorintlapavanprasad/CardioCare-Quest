import 'package:cardio_care_quest/features/dashboard/screens/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Add this line
import 'dart:math' as math;
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/theme/app_colors.dart';
import '../auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _outerRotationController;
  late AnimationController _innerRotationController;
  late AnimationController _pulseController;
 final bool _isDemoMode = true;
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _showButton = false;
    bool _isReturningUser = false; // ─── ADD THIS ───

  // ─── DEBUG HELPER ───
// ─── DEBUG HELPER ───
  void _showDebugAlert(String message) {
    // 1. Instantly log to the VS Code terminal
    debugPrint("🛠️ DEBUG: $message");
    
    // 2. Wait for the screen to finish building before showing the SnackBar
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
@override
  void initState() {
    super.initState();
    
    // 1. Only log to the terminal here, no visual popups during initState!
    debugPrint("🛠️ DEBUG: Splash Screen Initialized");
    
    _outerRotationController = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();
    _innerRotationController = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

    _initializeApp();
  }

Future<void> _initializeApp() async {
    await Future.delayed(const Duration(milliseconds: 1800));
 if (!mounted) return;
 if (_isDemoMode) {
      setState(() {
        _isReturningUser = false; // Forces the button to say "BEGIN JOURNEY"
        _showButton = true;       // Reveals the button
      });
      return; // Stops here! No background auth checks.
    }
    String? savedId = await _storage.read(key: 'participant_id');

    if (savedId != null && mounted) {
      debugPrint("🛠️ DEBUG: Found Local ID: $savedId. Verifying with server...");
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(savedId).get();
        if (userDoc.exists && mounted) {
          debugPrint("🛠️ DEBUG: Server Verified! Triggering Biometrics.");
          
          // ─── Mark as returning user before triggering lock ───
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
        debugPrint("🛠️ DEBUG: Network error. Defaulting to local biometric cache: $e");
        
        // ─── Mark as returning user even if offline ───
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
  
  
  
   Future<void> _triggerBiometricLogin() async {
    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Unlock to access Cardio Care Quest',
      );

      if (didAuthenticate && mounted) {
        _showDebugAlert("Biometrics Success -> Navigating to Dashboard");
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainLayout()), // Dashboard goes here
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

  @override
  void dispose() {
    _outerRotationController.dispose();
    _innerRotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

@override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.pageBackgroundGradient),
        child: SafeArea(
          // ─── CHANGED: Stack to Column to prevent overlapping ───
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3), // Pushes the logo down slightly from the very top
              
              // ─── LOGO GROUP ───
              // We keep the Stack HERE just for the layered logo parts
              SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildPetalRing(_outerRotationController, 260, 0.55, 18, 52),
                    _buildPetalRing(_innerRotationController, 200, 0.25, 10, 32, reverse: true),
                    ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.16).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)),
                      child: _buildCenterHeart(),
                    ),
                  ],
                ),
              ),
              
              const Spacer(flex: 2), // Creates flexible space between logo and text
              
              // ─── TEXT & BUTTON GROUP ───
              _buildBottomContent(),
              
              const Spacer(flex: 2), // Keeps the text from hitting the very bottom of the screen
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildPetalRing(AnimationController controller, double size, double opacity, double pWidth, double pHeight, {bool reverse = false}) {
    final colors = [AppColors.viridis0, AppColors.viridis1, AppColors.viridis2, AppColors.viridis3, AppColors.viridis4, AppColors.viridis3, AppColors.viridis2, AppColors.viridis1];
    return RotationTransition(
      turns: reverse ? ReverseAnimation(controller) : controller,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: List.generate(8, (i) => Transform.rotate(
            angle: (i * 45) * math.pi / 180,
            child: Align(alignment: Alignment.topCenter, child: Container(width: pWidth, height: pHeight, decoration: BoxDecoration(color: colors[i].withOpacity(opacity), borderRadius: const BorderRadius.vertical(top: Radius.circular(20), bottom: Radius.circular(15))))),
          )),
        ),
      ),
    );
  }

  Widget _buildCenterHeart() {
    return Container(
      width: 100, height: 100,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [AppColors.viridis4, AppColors.viridis3]), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)]),
      child: const Icon(Icons.favorite, color: AppColors.viridis0, size: 40),
    );
  }


Widget _buildBottomContent() {
    // ─── CHANGED: Removed Positioned, added Padding ───
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Cardio Care Quest', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 42, letterSpacing: -1)),
          const SizedBox(height: 8),
          Text('Welcome to Your Health Journey', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.placeholder, fontStyle: FontStyle.italic)),
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
                  shadowColor: AppColors.viridis4.withOpacity(0.5),
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
                  style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
 
}