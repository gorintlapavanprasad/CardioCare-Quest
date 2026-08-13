// login_screen.dart - returning-participant sign-in.
// Two paths: tap an NFC card (auto-fills the ID) or type it manually.
// Falls back to a local cache when offline. Clears old participant data first.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:cardio_care_quest/features/auth/auth_screen.dart';
import 'package:cardio_care_quest/features/dashboard/screens/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ─── ADDED: Official Netgauge Auth
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/firestore_paths.dart';
import '../../core/hooks/telemetry_hooks.dart';
import '../../core/services/nfc_service.dart';
import '../../core/services/activity_logs.dart';
import '../../core/services/offline_queue.dart';
// import 'auth_screen.dart'; // Uncomment if you still need this route

import 'package:cardio_care_quest/core/providers/user_data_manager.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _uniqueIdController = TextEditingController(); // the typed id box
  final NfcService _nfc = NfcService(); // reads the tap-card

  bool _isLoginLoading = false; // true while a login is in progress
  String? _currentUserDocId; // the matched account's id, once found

  // null until the hardware probe returns, so NFC-less devices don't flash the button.
  bool? _nfcAvailable;
  bool _nfcScanning = false;

  // Persistent banner below the NFC button. Replaces the old snackbar
  // which vanished before anyone could read it.
  _NfcStatus? _nfcStatus;

  @override
  void initState() {
    super.initState();
    _bootstrapNfc();
  }

  // Check for NFC support. Android also starts an ambient scan immediately;
  // iOS needs an explicit button tap (Core NFC requires a user gesture).
  Future<void> _bootstrapNfc() async {
    final available = await _nfc.isAvailable();
    if (!mounted) return;
    setState(() => _nfcAvailable = available);
    if (available && Platform.isAndroid) {
      unawaited(_runNfcScan(autoTriggered: true));
    }
  }

  @override
  void dispose() {
    _nfc.stopScan();
    _uniqueIdController.dispose();
    super.dispose();
  }

  // Run one NFC scan and pass the ID to _handleLogin.
  // autoTriggered=true for the Android ambient session on mount;
  // false when the participant pressed the button.
  Future<void> _runNfcScan({bool autoTriggered = false}) async {
    if (_nfcScanning || _isLoginLoading) return;
    setState(() {
      _nfcScanning = true;
      _nfcStatus = const _NfcStatus(
        level: _NfcStatusLevel.info,
        message:
            'Hold your NFC card to the back of the phone to log in.',
      );
    });

    unawaited(TelemetryHooks.logEvent(
      'nfc_scan_started',
      parameters: {'autoTriggered': autoTriggered},
    ));

    final id = await _nfc.startScan();
    final diagnostic = _nfc.lastDiagnostic;

    if (!mounted) return;
    setState(() => _nfcScanning = false);

    if (id == null || id.isEmpty) {
      setState(() {
        _nfcStatus = _NfcStatus(
          level: _NfcStatusLevel.warn,
          message: 'Card scanned but no Unique ID was found on it.',
          detail: diagnostic ??
              'No diagnostic available - the scan may have been '
              'cancelled before a tag was detected.',
        );
      });
      unawaited(TelemetryHooks.logEvent(
        'nfc_scan_no_id',
        parameters: {
          'autoTriggered': autoTriggered,
          'diagnostic': ?diagnostic,
        },
      ));
      // Restart the listener so they can just re-tap the card.
      if (autoTriggered && Platform.isAndroid && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted && !_nfcScanning && !_isLoginLoading) {
          unawaited(_runNfcScan(autoTriggered: true));
        }
      }
      return;
    }

    setState(() {
      _nfcStatus = _NfcStatus(
        level: _NfcStatusLevel.success,
        message: 'Read your card - logging in as $id...',
        detail: diagnostic,
      );
    });
    unawaited(TelemetryHooks.logEvent(
      'nfc_scan_id_read',
      parameters: {
        'id': id,
        'autoTriggered': autoTriggered,
        'diagnostic': ?diagnostic,
      },
    ));

    _uniqueIdController.text = id;
    await _handleLogin();

    // Still here means _handleLogin didn't navigate - login failed.
    // Mirror the error into the persistent banner (snackbar vanishes after ~4s).
    if (!mounted) return;
    setState(() {
      _nfcStatus = _NfcStatus(
        level: _NfcStatusLevel.error,
        message: 'Read "$id" from your card, but logging in failed.',
        detail:
            'See the message at the bottom of the screen. You can '
            'also enter the ID manually below to retry.',
      );
    });
    unawaited(TelemetryHooks.logEvent(
      'nfc_login_after_scan_failed',
      parameters: {'id': id, 'autoTriggered': autoTriggered},
    ));
  }

  // Clear the old participant's data, find this ID's account, then open the app.
  Future<void> _handleLogin() async {
    final uniqueId = _uniqueIdController.text.trim();
    final localContext = context;
    final messenger = ScaffoldMessenger.of(localContext);
    final navigator = Navigator.of(localContext);

    if (uniqueId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Please enter your Unique ID.")),
      );
      return;
    }

    setState(() => _isLoginLoading = true);

    // Clear old participant's data before the auth round-trip so
    // participant B can't briefly see A's data on a slow connection.
    Provider.of<UserDataProvider>(context, listen: false).clearData();

    // Best-effort sync of participant A's queue (~3s max), then clear it.
    // Leftover rows would sync under B's auth context and could fail
    // security rules, so we accept minor data loss for the outgoing user
    // over cross-participant contamination for the incoming one.
    final queue = GetIt.instance<OfflineQueue>();
    try {
      await queue.syncToFirestore().timeout(
            const Duration(seconds: 3),
            onTimeout: () {/* best effort; drop remainder below */},
          );
    } catch (_) { /* network down etc - proceed to clear */ }
    await queue.clear();
    try {
      await GetIt.instance<LoggingService>().clearLogs();
    } catch (_) { /* non-fatal */ }

    try {
      final firestore = FirebaseFirestore.instance;
      const storage = FlutterSecureStorage();
      final queue = GetIt.instance<OfflineQueue>();

      // Anonymous sign-in for auth; offline devices skip this and use cache.
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

      // Try direct doc lookup first; falls back to cache when offline.
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

      // No existing record found — create one if we're online.
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
        try {
          matchedDoc = await firestore
              .collection(FirestorePaths.userData)
              .doc(uniqueId)
              .get();
        } catch (_) {/* ignore */}
      }

      if (matchedDoc == null && !authedOnline) {
        // Offline and no cached record — can't proceed.
        throw Exception(
          "Can't reach the network and we don't have a cached record for "
          'this ID on this device. Connect to Wi-Fi and retry.',
        );
      }

      _currentUserDocId = matchedDoc?.id ?? uniqueId;

      // Queue the login timestamp — syncs when next online.
      await queue.enqueue(PendingOp.set(
        '${FirestorePaths.userData}/${_currentUserDocId!}',
        {
          'authUid': ?authUid,
          'lastLoginAt': OfflineFieldValue.nowTimestamp(),
        },
        merge: true,
      ));

      await storage.write(key: 'participant_id', value: uniqueId);

      if (!mounted) return;
      final userDataProvider = Provider.of<UserDataProvider>(
        context,
        listen: false,
      );

      await userDataProvider.fetchUserData(participantId: uniqueId);

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
                          // NFC section — hidden on devices without NFC.
                          if (_nfcAvailable == true) ...[
                            _buildPathLabel('AUTO LOGIN'),
                            const SizedBox(height: 8),
                            _buildNfcTapButton(),
                            if (_nfcStatus != null) ...[
                              const SizedBox(height: 12),
                              _buildNfcStatusBanner(_nfcStatus!),
                            ],
                            const SizedBox(height: 24),
                            _buildOrDivider(),
                            const SizedBox(height: 24),
                            _buildPathLabel('MANUAL LOGIN'),
                            const SizedBox(height: 8),
                          ],
                          _buildUniqueIdField(),
                          const SizedBox(height: 20),
                          _buildPrimaryButton(),
                          const SizedBox(height: 28),
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
  // Two soft faded circles behind everything, just for looks.
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

  // Text box for the participant's Unique ID.
  Widget _buildUniqueIdField() {
    return TextField(
      controller: _uniqueIdController,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: 'Unique ID',
        hintText: 'Enter your badge',
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        prefixIcon: Icon(
          Icons.badge_outlined,
          color: AppColors.viridis1.withValues(alpha: 0.6),
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

  // LOGIN button; shows a spinner while in progress.
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

  // Thin rainbow strip along the bottom of the card.
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

  // Small uppercase label above the AUTO / MANUAL login sections.
  Widget _buildPathLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: AppColors.viridis1.withValues(alpha: 0.75),
        ),
      ),
    );
  }

  // NFC tap button. On Android it's a backup to the auto-poll; on iOS
  // it's the only trigger (Core NFC needs a user gesture).
  Widget _buildNfcTapButton() {
    final scanning = _nfcScanning;
    final disabled = _isLoginLoading;
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: OutlinedButton(
        onPressed: (scanning || disabled) ? null : () => _runNfcScan(),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            scanning
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.contactless, size: 24),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                scanning
                    ? "Hold your card to the back of the phone..."
                    : "Tap your NFC card to log in",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // "or" divider between AUTO and MANUAL login paths.
  Widget _buildOrDivider() {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: AppColors.cardOutline, thickness: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            "or",
            style: TextStyle(
              color: AppColors.viridis1.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const Expanded(
          child: Divider(color: AppColors.cardOutline, thickness: 1),
        ),
      ],
    );
  }

  // Banner showing the latest NFC outcome (info/success/warn/error).
  // Stays visible until the next scan replaces it.
  Widget _buildNfcStatusBanner(_NfcStatus status) {
    final palette = _statusPalette(status.level);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(palette.icon, color: palette.foreground, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.message,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.foreground,
                    height: 1.35,
                  ),
                ),
                if (status.detail != null && status.detail!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    status.detail!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: palette.foreground.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static _NfcStatusPalette _statusPalette(_NfcStatusLevel level) {
    switch (level) {
      case _NfcStatusLevel.info:
        return const _NfcStatusPalette(
          background: Color(0xFFE7ECF6),
          border: Color(0xFFB7C4DD),
          foreground: Color(0xFF1F3A66),
          icon: Icons.contactless_outlined,
        );
      case _NfcStatusLevel.success:
        return const _NfcStatusPalette(
          background: Color(0xFFD6F5D8),
          border: Color(0xFF8FCB94),
          foreground: Color(0xFF1A5A1F),
          icon: Icons.check_circle_outline,
        );
      case _NfcStatusLevel.warn:
        return const _NfcStatusPalette(
          background: Color(0xFFFFF0C2),
          border: Color(0xFFE3C868),
          foreground: Color(0xFF7A4F00),
          icon: Icons.error_outline,
        );
      case _NfcStatusLevel.error:
        return const _NfcStatusPalette(
          background: Color(0xFFF8C3C8),
          border: Color(0xFFD18A91),
          foreground: Color(0xFF8A1A25),
          icon: Icons.cancel_outlined,
        );
    }
  }
}

// Severity of the NFC status banner — drives icon + colour.
enum _NfcStatusLevel { info, success, warn, error }

// Data backing the NFC status banner.
class _NfcStatus {
  final _NfcStatusLevel level;
  final String message;
  final String? detail;
  const _NfcStatus({
    required this.level,
    required this.message,
    this.detail,
  });
}

// Colour tokens for the status banner.
class _NfcStatusPalette {
  final Color background;
  final Color border;
  final Color foreground;
  final IconData icon;
  const _NfcStatusPalette({
    required this.background,
    required this.border,
    required this.foreground,
    required this.icon,
  });
}
