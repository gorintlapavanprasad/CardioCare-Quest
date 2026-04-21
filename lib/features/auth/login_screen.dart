import 'package:cardio_care_quest/features/auth/auth_screen.dart';
import 'package:cardio_care_quest/features/dashboard/screens/main_layout.dart';
import 'package:cardio_care_quest/features/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ─── ADDED: Official Netgauge Auth
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
// import 'auth_screen.dart'; // Uncomment if you still need this route
// Routing to the HomeTab

import 'package:cardio_care_quest/user_data_manager.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ─── CHANGED: Using Email/Password to match Netgauge backend ───
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoginLoading = false;
  bool _isDemoLoading = false;

  // Set to true to hide passwords and enable 1-tap visitor access.
  final bool _isDemoMode = true;

  /// ─── NEW: Official Firebase Anonymous Login for Visitors ───
 /// ─── UPDATED: Official Firebase Anonymous Login (SKIPPING ONBOARDING) ───

// --- UPDATED: Decision Logic for Quick Login ---
// --- UPDATED: Decision Logic for Quick Login (Netgauge Hybrid) ---
  Future<void> _handleQuickLogin() async {
    setState(() => _isDemoLoading = true);
    try {
      UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
      User user = userCredential.user!;

      final firestore = FirebaseFirestore.instance;
      // ─── CHANGED: Point to 'users' collection ───
      final userRef = firestore.collection('users').doc(user.uid);
      final doc = await userRef.get();

      // ⚡ FUNDAMENTAL FIX: Only set defaults if the user is brand new
      if (!doc.exists) {
        final batch = firestore.batch();

        batch.set(userRef, {
          'uid': user.uid,
          'email': 'guest_${user.uid.substring(0, 5)}@demo.com', 
          'basicInfo': {'firstName': 'Explorer'},
          'totalXP': 0, 
          'totalSessions': 0,
          'totalDistance': 0,
        });

        final leaderboardRef = firestore.collection('leaderboard').doc(user.uid);
        batch.set(leaderboardRef, {
          'userId': user.uid,
          'score': 0,
          'totalDistance': 0,
          'rank': 0,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        await batch.commit();
      }

      if (mounted) {
        await Provider.of<UserDataProvider>(context, listen: false).fetchUserData();
        _navigateToCorrectScreen(user.uid);
      }
    } catch (e) {
      if (mounted) setState(() => _isDemoLoading = false);
    }
  }

  // --- NEW: The Central Decision Engine ---
  Future<void> _navigateToCorrectScreen(String uid) async {
    final onboardingDoc = await FirebaseFirestore.instance
        .collection('ABC_Onboarding')
        .doc('user')
        .collection(uid)
        .doc('flags')
        .get();

    if (mounted) {
      if (onboardingDoc.exists && onboardingDoc.data()?['play_message'] == true) {
        // User is a veteran -> Go to Home
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainLayout()));
      } else {
        // User is new -> Go to Onboarding
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
      }
    }
  }

Future<void> _handleLogin() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) return;

    setState(() => _isLoginLoading = true);

    try {
      // 1. Authenticate via Firebase
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (mounted) {
        // 2. Load the data into the Netgauge Provider
        await Provider.of<UserDataProvider>(context, listen: false).fetchUserData();
        
        // 3. Check Onboarding Status
        final user = FirebaseAuth.instance.currentUser!;
        final onboardingDoc = await FirebaseFirestore.instance
            .collection('ABC_Onboarding')
            .doc('user')
            .collection(user.uid)
            .doc('flags')
            .get();

        if (onboardingDoc.exists && onboardingDoc.data()?['play_message'] == true) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainLayout()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login Failed: ${e.toString().split(']').last}")),
        );
        setState(() => _isLoginLoading = false);
      }
    }
  }

  @override
 @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          _buildBackgroundDecoration(),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 400),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.cardBorder.withOpacity(0.5)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          _buildHeaderIcon(),
                          const SizedBox(height: 24),
                          Text(
                            "Cardio Care Quest",
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                                  fontSize: 30,
                                  color: const Color(0xFF2D3A5E),
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 32),
                          _buildTextField(_emailController, "Email Address", Icons.email_outlined),
                          if (!_isDemoMode) ...[
                            const SizedBox(height: 12),
                            _buildTextField(_passwordController, "Password", Icons.lock_outline, isPassword: true),
                          ],
                          const SizedBox(height: 20),
                          _buildPrimaryButton(),
                          const SizedBox(height: 24),
                          _buildDivider(),
                          const SizedBox(height: 20),
                          if (_isDemoMode) ...[
                            _buildDemoButton(),
                            const SizedBox(height: 8),
                          ],
                          
                          // --- RESTORED: Join the Circle Button ---
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (context) => const AuthScreen(), // Adjust to your actual screen name
                                // builder: (context) => const Scaffold(body: Center(child: Text("SignUp Screen"))), 
                              ),
                            ),
                            child: const Text(
                              "New user? Join the Circle",
                              style: TextStyle(
                                color: AppColors.activeTeal,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildBottomGradientBar(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  // --- UI SUB-WIDGETS ---

  Widget _buildBackgroundDecoration() {
    return Stack(
      children: [
        Positioned(
          top: -120, right: -100,
          child: Container(width: 480, height: 480, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.viridis3.withOpacity(0.07))),
        ),
        Positioned(
          bottom: -80, left: -80,
          child: Container(width: 360, height: 360, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.viridis2.withOpacity(0.07))),
        ),
      ],
    );
  }

  Widget _buildHeaderIcon() {
    return Container(
      width: 72, height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [AppColors.viridis4, AppColors.viridis3]),
        boxShadow: [BoxShadow(color: AppColors.viridis3.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: const Icon(Icons.favorite, color: AppColors.viridis0, size: 32),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isPassword ? TextInputType.text : TextInputType.emailAddress,
      decoration: InputDecoration(
        counterText: "",
        prefixIcon: Icon(icon, color: AppColors.viridis1.withOpacity(0.5)),
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.cardOutline, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.activeTeal, width: 2),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton() {
    return SizedBox(
      width: double.infinity, height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.viridis4,
          foregroundColor: AppColors.viridis0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        onPressed: (_isDemoLoading || _isLoginLoading) ? null : _handleLogin,
        child: _isLoginLoading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.viridis0))
            : const Text("ENTER THE QUEST", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(thickness: 1)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text("OR", style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.bold))),
        const Expanded(child: Divider(thickness: 1)),
      ],
    );
  }

  Widget _buildDemoButton() {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.viridis2,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          shadowColor: AppColors.viridis2.withOpacity(0.4),
        ),
        onPressed: (_isDemoLoading || _isLoginLoading) ? null : _handleQuickLogin,
        child: _isDemoLoading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text("QUICK VISITOR DEMO", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
      ),
    );
  }

  Widget _buildBottomGradientBar() {
    return Container(
      height: 4, width: double.infinity,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        gradient: LinearGradient(colors: [AppColors.viridis0, AppColors.viridis1, AppColors.viridis2, AppColors.viridis3, AppColors.viridis4]),
      ),
    );
  }
}