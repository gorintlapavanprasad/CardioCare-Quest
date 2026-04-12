import 'package:cardio_care_quest/features/dashboard/screens/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/theme/app_colors.dart';
import 'auth_screen.dart';
import 'auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  bool _isLoginLoading = false;
  bool _isDemoLoading = false;

  // Set to true to hide passwords and enable 1-tap visitor access.
  final bool _isDemoMode = true;

  /// Handles the 1-Tap "Quick Demo" visitor flow
  /// UPDATED: Includes self-healing counters and basicInfo structure
  Future<void> _handleQuickLogin() async {
    setState(() => _isDemoLoading = true);

    int newGuestNumber = 1;

    try {
      final counterRef = FirebaseFirestore.instance
          .collection('metadata')
          .doc('counters');

      // ─── SELF-HEALING TRANSACTION ───
      newGuestNumber = await FirebaseFirestore.instance.runTransaction((
        transaction,
      ) async {
        DocumentSnapshot snapshot = await transaction.get(counterRef);

        if (!snapshot.exists) {
          transaction.set(counterRef, {'guestCount': 1});
          return 1;
        }

        int currentCount =
            (snapshot.data() as Map<String, dynamic>)['guestCount'] ?? 0;
        int newCount = currentCount + 1;
        transaction.update(counterRef, {'guestCount': newCount});
        return newCount;
      });
    } catch (e) {
      debugPrint("Error fetching guest counter: $e");
      newGuestNumber = DateTime.now().millisecond;
    }

    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String deviceId = "Visitor";

    try {
      if (kIsWeb) {
        WebBrowserInfo webInfo = await deviceInfo.webBrowserInfo;
        deviceId = "G${newGuestNumber}_Web_${webInfo.browserName.name}";
      } else if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceId =
            "G${newGuestNumber}_${androidInfo.model.replaceAll(" ", "")}";
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceId =
            "G${newGuestNumber}_${iosInfo.utsname.machine.replaceAll(" ", "")}";
      }
    } catch (e) {
      deviceId = "Guest_$newGuestNumber";
    }

    // ─── FIXED: Save with basicInfo structure ───
    await FirebaseFirestore.instance.collection('users').doc(deviceId).set({
      'participantId': deviceId,
      'basicInfo': {'firstName': 'Guest $newGuestNumber'},
      'status': 'visitor_demo',
      'createdAt': FieldValue.serverTimestamp(),
      'xp': 0,
    }, SetOptions(merge: true));

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('participant_id', deviceId);
      debugPrint("✅ Saved ID: $deviceId");
    } catch (e) {
      debugPrint("❌ Storage Error: $e");
    }

    if (mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.updateField('participant_id', deviceId);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainLayout()),
      );
    }
  }

  /// Handles manual Participant ID login
  Future<void> _handleLogin() async {
    String participantId = _idController.text.trim();
    String pin = _pinController.text.trim();

    if (participantId.isEmpty) return;

    setState(() => _isLoginLoading = true);

    if (_isDemoMode) {
      try {
        // ─── FIXED: Ensure existing IDs also have basicInfo for Home ───
        await FirebaseFirestore.instance
            .collection('users')
            .doc(participantId)
            .set({
              'participantId': participantId,
              'basicInfo': {
                'firstName': participantId, // Fallback name
              },
              'status': 'active_demo',
              'lastLogin': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('participant_id', participantId);

        if (mounted) {
          final authProvider = Provider.of<AuthProvider>(
            context,
            listen: false,
          );
          authProvider.updateField('participant_id', participantId);

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MainLayout()),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Connection error.")));
          setState(() => _isLoginLoading = false);
        }
      }
      return;
    }

    // Standard PIN login flow
    if (pin.isEmpty) {
      setState(() => _isLoginLoading = false);
      return;
    }

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(participantId)
          .get();

      if (doc.exists && doc.get('transferPin') == pin) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('participant_id', participantId);

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MainLayout()),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Incorrect ID or PIN.")));
          setState(() => _isLoginLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Network error.")));
        setState(() => _isLoginLoading = false);
      }
    }
  }

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
                  border: Border.all(
                    color: AppColors.cardBorder.withOpacity(0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
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
                            style: Theme.of(context).textTheme.displayLarge
                                ?.copyWith(
                                  fontSize: 30,
                                  color: const Color(0xFF2D3A5E),
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 32),

                          _buildTextField(
                            _idController,
                            "Participant ID",
                            Icons.person_outline,
                          ),
                          if (!_isDemoMode) ...[
                            const SizedBox(height: 12),
                            _buildTextField(
                              _pinController,
                              "Password",
                              Icons.lock_outline,
                              isPin: true,
                            ),
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

                          TextButton(
                            onPressed: () =>
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (context) => const AuthScreen(),
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
          top: -120,
          right: -100,
          child: Container(
            width: 480,
            height: 480,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.viridis3.withOpacity(0.07),
            ),
          ),
        ),
        Positioned(
          bottom: -80,
          left: -80,
          child: Container(
            width: 360,
            height: 360,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.viridis2.withOpacity(0.07),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderIcon() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.viridis4, AppColors.viridis3],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.viridis3.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(Icons.favorite, color: AppColors.viridis0, size: 32),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool isPin = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPin,
      maxLength: isPin ? 4 : null,
      keyboardType: isPin ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        counterText: "",
        prefixIcon: Icon(icon, color: AppColors.viridis1.withOpacity(0.5)),
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AppColors.cardOutline,
            width: 1.5,
          ),
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
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.viridis4,
          foregroundColor: AppColors.viridis0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
        ),
        onPressed: (_isDemoLoading || _isLoginLoading) ? null : _handleLogin,
        child: _isLoginLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.viridis0,
                ),
              )
            : const Text(
                "ENTER THE QUEST",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "OR",
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Expanded(child: Divider(thickness: 1)),
      ],
    );
  }

  Widget _buildDemoButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.viridis2,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
          shadowColor: AppColors.viridis2.withOpacity(0.4),
        ),
        onPressed: (_isDemoLoading || _isLoginLoading)
            ? null
            : _handleQuickLogin,
        child: _isDemoLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                "QUICK VISITOR DEMO",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
      ),
    );
  }

  Widget _buildBottomGradientBar() {
    return Container(
      height: 4,
      width: double.infinity,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        gradient: LinearGradient(
          colors: [
            AppColors.viridis0,
            AppColors.viridis1,
            AppColors.viridis2,
            AppColors.viridis3,
            AppColors.viridis4,
          ],
        ),
      ),
    );
  }
}
