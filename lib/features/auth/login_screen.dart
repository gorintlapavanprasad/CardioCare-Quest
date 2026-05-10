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
// Routing to the HomeTab

import 'package:cardio_care_quest/core/providers/user_data_manager.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _uniqueIdController = TextEditingController();
  final NfcService _nfc = NfcService();

  bool _isLoginLoading = false;
  String? _currentUserDocId;

  // NFC state — `_nfcAvailable` stays null until the capability probe
  // returns so the UI doesn't briefly flash the NFC button on iPads /
  // NFC-less devices before resolving to the manual-only layout.
  bool? _nfcAvailable;
  bool _nfcScanning = false;

  /// Inline status banner shown above the NFC button. Replaces the
  /// fleeting snackbar feedback we used to rely on — earlier the
  /// research team hit "scanned but nothing happened" because the
  /// auto-triggered scan would silently swallow parse failures, and
  /// any login error that fired afterwards used a snackbar that
  /// disappeared in a few seconds. The banner persists until the
  /// next NFC outcome (success, failure, retry), so the participant
  /// always has a clear signal about what just happened.
  _NfcStatus? _nfcStatus;

  @override
  void initState() {
    super.initState();
    _bootstrapNfc();
  }

  /// Probe the device for NFC support. On Android we ALSO start an
  /// ambient scan immediately so the participant can simply tap their
  /// card with no button press required (auto-login). iOS requires
  /// an explicit user gesture to invoke Core NFC, so on iOS the
  /// participant has to tap the "Tap NFC card" button first — same
  /// button works on Android too as a fallback.
  Future<void> _bootstrapNfc() async {
    final available = await _nfc.isAvailable();
    if (!mounted) return;
    setState(() => _nfcAvailable = available);
    if (available && Platform.isAndroid) {
      // Fire-and-forget. Auto-triggered scans silently swallow
      // failures (e.g. timeout) so the participant isn't pestered
      // with snackbars they never asked for.
      unawaited(_runNfcScan(autoTriggered: true));
    }
  }

  @override
  void dispose() {
    // Cancel any in-flight scan before tearing down so the bridge
    // doesn't outlive the screen. _nfc.stopScan is idempotent.
    _nfc.stopScan();
    _uniqueIdController.dispose();
    super.dispose();
  }

  /// Drive an NFC scan to completion and feed the resulting ID into
  /// the existing [_handleLogin] flow. [autoTriggered] is true for
  /// the ambient Android session that starts on screen mount, and
  /// false when the participant pressed the button explicitly.
  ///
  /// Both paths surface visible feedback now (the inline status
  /// banner). Earlier the auto-triggered scan would swallow parse
  /// failures so the participant was left wondering whether the
  /// chime they heard meant anything.
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
      // Surface the diagnostic from NfcService so the team can see
      // WHY the card didn't read (no NDEF, unsupported types, empty
      // payload, etc.) instead of a generic "couldn't read" message.
      // Same banner copy for autoTriggered and manual scans now —
      // silent failures on the Android auto-scan were the original
      // bug report.
      setState(() {
        _nfcStatus = _NfcStatus(
          level: _NfcStatusLevel.warn,
          message: 'Card scanned but no Unique ID was found on it.',
          detail: diagnostic ??
              'No diagnostic available — the scan may have been '
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
      // Restart the ambient listener so the participant can simply
      // re-tap. Previously after a failed auto-scan they'd have to
      // press the manual button; on a real device with a good tag
      // most "failures" are actually mis-taps (off-axis, too quick)
      // that succeed on a second try.
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
        message: 'Read your card — logging in as $id…',
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

    // If we're still on the screen after _handleLogin, the login
    // path didn't navigate — usually because Firestore threw and
    // _handleLogin's catch block surfaced a snackbar. The snackbar
    // disappears after ~4s, so we mirror the failure into the
    // persistent banner so the participant has lasting context for
    // what they just saw at the bottom of the screen.
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

    // Drop any leftover user state from the previous session BEFORE
    // we kick off the auth + fetch round-trip. Without this, a
    // pre-existing UserDataProvider map from participant A would
    // remain visible to readers (dashboard, WebView host's UA
    // stamp, GET_TODAY_BP bridge handler) for the entire duration
    // of the Firestore query — long enough on a slow connection
    // for participant B to land on the dashboard, open Vascular
    // Village, and have the WebView's UA + localStorage tagged
    // with A's UID. fetchUserData below also performs this wipe
    // when it detects a participant switch, but doing it here
    // makes the leak window zero-length even if the await chain
    // gets reordered by a future refactor.
    Provider.of<UserDataProvider>(context, listen: false).clearData();

    // Drain the persistent Hive queues before swapping participants.
    // OfflineQueue + activity_logs are global singletons; if A had
    // unsynced writes when their session ended, those rows sit in
    // the same Hive box B now uses. The path strings are baked in
    // at enqueue time (e.g. `userData/A/dailyLogs/...`) so they'd
    // sync to A's record correctly — but they'd sync under B's
    // Firebase auth context, which can fail security rules and
    // leave A's data permanently stuck in the queue.
    //
    // Strategy: try ONE quick best-effort sync to flush A's writes
    // (max ~3s — short enough that the participant doesn't notice),
    // then drop whatever's left. We deliberately accept the risk of
    // dropping a few unsynced writes for the outgoing participant
    // over the certainty of cross-participant queue contamination
    // for the incoming one. Same pattern for activity_logs.
    final queue = GetIt.instance<OfflineQueue>();
    try {
      await queue.syncToFirestore().timeout(
            const Duration(seconds: 3),
            onTimeout: () {/* best effort; drop remainder below */},
          );
    } catch (_) { /* network down etc — proceed to clear */ }
    await queue.clear();
    try {
      await GetIt.instance<LoggingService>().clearLogs();
    } catch (_) { /* non-fatal */ }

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
                          // Auto-login (NFC) section — only rendered
                          // when the device actually supports it.
                          // iPads + NFC-less Androids skip straight
                          // to the manual entry below, so they never
                          // see a non-functional button.
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

  /// Section label sitting above the AUTO and MANUAL paths so
  /// participants can tell at a glance which area is which. Subtle —
  /// uppercase, small, muted — so it doesn't compete with the
  /// primary buttons for attention.
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

  /// NFC tap-to-login button. Visible only when [_nfcAvailable] is
  /// true (i.e. the device has NFC hardware switched on). On Android
  /// this is a redundant back-up to the auto-poll that fired when the
  /// screen mounted; on iOS it's the only entry point since Apple's
  /// Core NFC requires an explicit user gesture per scan session.
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
                    ? "Hold your card to the back of the phone…"
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

  /// Visual separator between AUTO and MANUAL login paths.
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

  /// Inline banner that displays the most recent NFC outcome under
  /// the NFC tap button. Persists across re-renders until the next
  /// scan replaces it. Color + icon vary by [_NfcStatusLevel] so the
  /// participant can read the state at a glance:
  ///   * info     — neutral blue (scan started, ambient listener)
  ///   * success  — green (id read, login starting)
  ///   * warn     — amber  (tag read, no id; or autoTriggered restart)
  ///   * error    — red    (login failed after a successful read)
  ///
  /// `detail` is rendered below the headline in smaller text — for
  /// info / success it's the NfcService diagnostic ("Parsed NDEF
  /// Text record → 'P-001'"), for warn / error it's actionable next-
  /// step copy or the diagnostic from the failed parse so the
  /// research team can debug without logcat.
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

/// Severity of the NFC status banner — drives icon + colour.
enum _NfcStatusLevel { info, success, warn, error }

/// Plain-data row backing the inline NFC status banner. Stored in
/// state instead of triggered through a snackbar so the message
/// persists until the participant takes their next action — earlier
/// the team's "scanned but nothing happened" reports were partly
/// because the snackbar evidence vanished after 4 seconds and they
/// never saw it.
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

/// Visual tokens used by the status banner — kept as a small struct
/// so the level→colour map lives in one place.
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
