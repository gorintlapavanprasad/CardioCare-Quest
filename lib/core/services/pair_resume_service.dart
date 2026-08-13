import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/hooks/pair_hooks.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';
import 'package:cardio_care_quest/core/services/session_settings_service.dart';

// pair_resume_service.dart - if a participant + caregiver session was running when
// the app closed, this restores it on the next open.

// Restores a paired session (session context + display settings) after a cold restart.
class PairResumeService {
  PairResumeService._();
  static final PairResumeService instance = PairResumeService._();

  static const _storage = FlutterSecureStorage();

  // Sessions inactive for more than 6 hours are not resumed.
  static const resumeWindow = Duration(hours: 6);

  // Try to restore a paired session from secure storage. Returns the session id, or null.
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

      // If inactive for over 6 hours, leave the record but don't reattach.
      final lastActive = data['lastActiveAt'];
      if (lastActive is Timestamp &&
          DateTime.now().difference(lastActive.toDate()) > resumeWindow) {
        await _clear();
        return null;
      }

      // Restore the session and its display settings.
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
