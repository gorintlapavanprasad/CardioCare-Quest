import 'package:cardio_care_quest/features/auth/auth_screen.dart';
import 'package:cardio_care_quest/features/dashboard/screens/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ─── ADDED: Official Netgauge Auth
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/firestore_paths.dart';
import '../../core/services/offline_queue.dart';
// import 'auth_screen.dart'; // Uncomment if you still need this route
// Routing to the HomeTab

import 'package:cardio_care_quest/core/providers/user_data_manager.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _uniqueIdController = TextEditingController();

  bool _isLoginLoading = false;
  String? _currentUserDocId;

  Future<void> _openScannerForUniqueId() async {
    final navigator = Navigator.of(context);
    final result = await navigator.push<String?>(
      MaterialPageRoute(builder: (_) => const UniqueIdScannerScreen()),
    );

    if (!mounted) return;
    if (result != null && result.trim().isNotEmpty) {
      _uniqueIdController.text = result.trim();
    }
  }

  @override
  void dispose() {
    _uniqueIdController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final uniqueId = _uniqueIdController.text.trim();
    final localContext = context;
    final messenger = ScaffoldMessenger.of(localContext);
    final navigator = Navigator.of(localContext);

    if (uniqueId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Please enter or scan your Unique ID.")),
      );
      return;
    }

    setState(() => _isLoginLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      const storage = FlutterSecureStorage();
      final queue = GetIt.instance<OfflineQueue>();

      // Best-effort anonymous sign-in. Required for first-time auth, but if
      // the device is offline we may still be able to log in a returning
      // participant via Firestore's local cache (case 9).
      String? authUid;
      bool authedOnline = false;
      try {
        await FirebaseAuth.instance.signOut();
        final credential = await FirebaseAuth.instance.signInAnonymously();
        authUid = credential.user?.uid;
        authedOnline = authUid != null;
      } catch (e) {
        debugPrint('Login: anonymous auth failed (likely offline): $e');
      }

      DocumentSnapshot<Map<String, dynamic>>? matchedDoc;

      // First check for a document whose ID matches the entered unique ID.
      // .get() uses Source.serverAndCache by default — falls back to cache
      // if the device is offline, but only if the doc was previously fetched.
      try {
        final directDoc = await firestore
            .collection(FirestorePaths.userData)
            .doc(uniqueId)
            .get();
        if (directDoc.exists) {
          matchedDoc = directDoc;
        }
      } catch (_) {/* offline + uncached → try query next */}

      if (matchedDoc == null) {
        try {
          final query = await firestore
              .collection(FirestorePaths.userData)
              .where('participantId', isEqualTo: uniqueId)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            matchedDoc = query.docs.first;
          }
        } catch (_) {/* offline + uncached query → fall through */}
      }

      // Brand-new participant on a brand-new device. We need to be ONLINE for
      // this branch because there's no cached doc to fall back to. If we
      // succeeded with anonymous auth above, attempt the create.
      if ((matchedDoc == null || !matchedDoc.exists) && authedOnline) {
        await queue.enqueue(PendingOp.set(
          '${FirestorePaths.userData}/$uniqueId',
          {
            'uid': uniqueId,
            'participantId': uniqueId,
            'basicInfo': {'firstName': 'Explorer'},
            'measurementsTaken': 0,
            'distanceTraveled': 0,
            'dataPoints': [],
            'radGyration': 0,
            'points': 0,
            'totalSessions': 0,
            'totalDistance': 0,
            'createdAt': OfflineFieldValue.nowTimestamp(),
          },
          merge: true,
        ));
        // Re-fetch from cache now that the queue applied locally as well.
        try {
          matchedDoc = await firestore
              .collection(FirestorePaths.userData)
              .doc(uniqueId)
              .get();
        } catch (_) {/* ignore */}
      }

      if (matchedDoc == null && !authedOnline) {
        // Truly stuck — offline and no cached match for this ID.
        throw Exception(
          "Can't reach the network and we don't have a cached record for "
          'this ID on this device. Connect to Wi-Fi and retry.',
        );
      }

      _currentUserDocId = matchedDoc?.id ?? uniqueId;

      // Always queue the auth/login update — it's idempotent and will sync
      // whenever the device next has connectivity.
      await queue.enqueue(PendingOp.set(
        '${FirestorePaths.userData}/${_currentUserDocId!}',
        {
          'authUid': ?authUid,
          'lastLoginAt': OfflineFieldValue.nowTimestamp(),
        },
        merge: true,
      ));

      // Cache the participant ID for offline-friendly relaunches.
      await storage.write(key: 'participant_id', value: uniqueId);

      if (!mounted) return;
      final userDataProvider = Provider.of<UserDataProvider>(
        context,
        listen: false,
      );

      await userDataProvider.fetchUserData(participantId: uniqueId);

      if (!mounted) return;
      await _showBmiDialogIfNeeded(context);

      if (!mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const MainLayout()),
      );
    } catch (e) {
      if (mounted) {
        final message = e is FirebaseAuthException
            ? e.message ?? 'Unable to log in. Please try again.'
            : e.toString().replaceAll('Exception: ', '');

        messenger.showSnackBar(SnackBar(content: Text(message)));
        setState(() => _isLoginLoading = false);
      }
    }
  }

  Future<void> _showBmiDialogIfNeeded(BuildContext localContext) async {
    final userDataProvider = Provider.of<UserDataProvider>(
      localContext,
      listen: false,
    );
    final currentData = userDataProvider.userData ?? {};
    if (currentData['heightCm'] != null ||
        currentData['weightKg'] != null ||
        currentData['bmi'] != null) {
      return;
    }

    final TextEditingController heightController = TextEditingController();
    final TextEditingController weightController = TextEditingController();

    final result = await showDialog<bool>(
      context: localContext,
      barrierDismissible: false,
      builder: (context) {
        final messenger = ScaffoldMessenger.of(context);
        final dialogNavigator = Navigator.of(context);
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Tell us about you',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter height and weight to personalize your experience.',
                style: TextStyle(color: AppColors.subtitle, fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: heightController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Height (cm)',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: weightController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Weight (kg)',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AppColors.background,
                minimumSize: const Size(120, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Skip for now',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.subtitle,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.viridis4,
                minimumSize: const Size(120, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () async {
                final height = int.tryParse(heightController.text.trim());
                final weight = double.tryParse(weightController.text.trim());
                if (height == null ||
                    height <= 0 ||
                    weight == null ||
                    weight <= 0) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please enter valid height and weight or tap Skip.',
                      ),
                    ),
                  );
                  return;
                }
                final bmi = weight / ((height / 100) * (height / 100));
                final docId = _currentUserDocId ?? currentData['uid'];
                if (docId != null) {
                  await GetIt.instance<OfflineQueue>().enqueue(PendingOp.set(
                    '${FirestorePaths.userData}/$docId',
                    {
                      'heightCm': height,
                      'weightKg': weight,
                      'bmi': double.parse(bmi.toStringAsFixed(1)),
                    },
                    merge: true,
                  ));
                }
                if (!mounted) return;
                dialogNavigator.pop(true);
              },
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await userDataProvider.fetchUserData(
        participantId: _uniqueIdController.text.trim(),
      );
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
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppColors.cardBorder.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
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
                          // _buildHeaderIcon(),
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
                          _buildUniqueIdField(),
                          const SizedBox(height: 20),
                          _buildPrimaryButton(),
                          const SizedBox(height: 28),
                          // --- RESTORED: Join the Circle Button ---
                          TextButton(
                            onPressed: () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const AuthScreen(), // Adjust to your actual screen name
                                // builder: (context) => const Scaffold(body: Center(child: Text("SignUp Screen"))),
                              ),
                            ),
                            child: const Text(
                              "New user? Join the Circle",
                              style: TextStyle(
                                color: AppColors.primary,
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
              color: AppColors.viridis3.withValues(alpha: 0.07),
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
              color: AppColors.viridis2.withValues(alpha: 0.07),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUniqueIdField() {
    return TextField(
      controller: _uniqueIdController,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: 'Unique ID',
        hintText: 'Enter or scan your badge',
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        prefixIcon: Icon(
          Icons.badge_outlined,
          color: AppColors.viridis1.withValues(alpha: 0.6),
        ),
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner),
          color: AppColors.viridis4,
          tooltip: 'Scan QR/Barcode',
          onPressed: _openScannerForUniqueId,
        ),
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
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
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
        onPressed: _isLoginLoading ? null : _handleLogin,
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
                "LOGIN",
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

class UniqueIdScannerScreen extends StatelessWidget {
  const UniqueIdScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Scan QR/Barcode',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final code = barcodes.first.rawValue;
            if (code != null && code.trim().isNotEmpty) {
              Navigator.of(context).pop(code.trim());
            }
          }
        },
      ),
    );
  }
}
