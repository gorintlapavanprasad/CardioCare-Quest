import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/hooks/pair_hooks.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';
import 'package:cardio_care_quest/core/services/session_settings_service.dart';

// pair_resume_service.dart - if a two-player (participant + caregiver) session was
// going and the app got closed, this brings it back when the app reopens.

/// Reattaches a paired session after a cold restart.
///
/// The write durability is already handled by OfflineQueue + Firestore
/// persistence, so "span leaving the device and returning" mostly works at the
/// data layer. This service restores the *session context* (SessionManager +
/// text-size/pace settings) so the UI knows a co-play session is still live.
class PairResumeService {
  PairResumeService._();
  static final PairResumeService instance = PairResumeService._();

  static const _storage = FlutterSecureStorage();

  /// Sessions older than this since `lastActiveAt` are treated as stale and
  /// not auto-resumed.
  static const resumeWindow = Duration(hours: 6);

  /// Try to restore an active paired session. Safe to call at startup; a no-op
  /// when there is nothing to resume. Returns the restored id, or null.
  Future<String?> tryRestore() async {
    String? id;
    try {
      id = await _storage.read(key: PairHooks.activePairKey);
    } catch (e) {
      debugPrint('PairResumeService: secure-storage read failed - $e');
      return null;
    }
    if (id == null || id.isEmpty) return null;

    try {
      final snap = await FirebaseFirestore.instance
          .collection(FirestorePaths.pairedSessions)
          .doc(id)
          .get();
      final data = snap.data();
      if (data == null || data['status'] == 'ended') {
        await _clear();
        return null;
      }

      // If the session hasn't been touched in over 6 hours, treat it as too old.
      final lastActive = data['lastActiveAt'];
      if (lastActive is Timestamp &&
          DateTime.now().difference(lastActive.toDate()) > resumeWindow) {
        // Too old - leave the record intact for research but don't reattach.
        await _clear();
        return null;
      }

      // Good to resume: put the session and its settings (text size, pace) back.
      SessionManager.restorePairedSession(
        pairedSessionId: id,
        participantId: (data['participantId'] as String?) ?? '',
        caregiverId: data['caregiverId'] as String?,
        caregiverLabel: data['caregiverLabel'] as String?,
      );
      SessionSettingsService.instance.apply(
        SessionSettings.fromMap(data['settings'] as Map<String, dynamic>?),
      );
      await PairHooks.resume();
      debugPrint('PairResumeService: resumed paired session $id');
      return id;
    } catch (e) {
      debugPrint('PairResumeService: restore failed - $e');
      return null;
    }
  }

  // Forget the saved "session in progress" pointer on the phone.
  Future<void> _clear() async {
    try {
      await _storage.delete(key: PairHooks.activePairKey);
    } catch (_) {/* best effort */}
  }
}
