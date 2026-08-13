import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';

// PairHooks - manages a paired (participant + caregiver) session.
// One session record ties all events/surveys/walks together by session id.
// TelemetryHooks adds the id automatically so callers don't have to.
// Writes go through OfflineQueue so this works offline.
abstract class PairHooks {
  // Shared write queue.
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  // Session id persisted on the phone so a restart can find and resume it.
  static const activePairKey = 'active_pair_session';
  static const _storage = FlutterSecureStorage();

  // Start a paired session. Returns the new session id.
  static Future<String> start({
    required String participantId,
    String? caregiverId,
    String? caregiverLabel,
    Map<String, dynamic>? settings,
    String? deviceTag,
  }) async {
    // Activate the session. Events from this point carry its id.
    final id = SessionManager.startPairedSession(
      participantId: participantId,
      caregiverId: caregiverId,
      caregiverLabel: caregiverLabel,
    );

    // "lastActiveAt" is a heartbeat timestamp used to decide if resuming is safe.
    final record = <String, dynamic>{
      'pairedSessionId': id,
      'participantId': participantId,
      'caregiverId': caregiverId,
      'caregiverLabel': caregiverLabel,
      'status': 'active',
      'startedAt': OfflineFieldValue.nowTimestamp(),
      'lastActiveAt': OfflineFieldValue.nowTimestamp(),
      if (deviceTag != null) 'deviceTag': deviceTag,
      if (settings != null) 'settings': settings,
      'helpMarkerCount': 0, // grows each time the caregiver marks "I helped".
    };

    // Save to two places in one batch: top-level and under the participant.
    await _queue.enqueueBatch([
      // 1) Top-level pairedSessions collection.
      PendingOp.set('${FirestorePaths.pairedSessions}/$id', record, merge: true),
      // 2) Under the participant for quick per-person lookups.
      PendingOp.set(
        '${FirestorePaths.userData}/$participantId/'
        '${FirestorePaths.pairedSessions}/$id',
        record,
        merge: true,
      ),
    ]);

    // Persist the session id on the phone. Storage failures are non-fatal.
    try {
      await _storage.write(key: activePairKey, value: id);
    } catch (e) {
      debugPrint('PairHooks: could not persist active-pair pointer - $e');
    }
    return id;
  }

  // Heartbeat: update lastActiveAt. No-op if no session is running.
  static Future<void> touch() {
    final id = SessionManager.pairedSessionId;
    if (id == null) return Future.value();
    return _queue.enqueue(PendingOp.set(
      '${FirestorePaths.pairedSessions}/$id',
      {'lastActiveAt': OfflineFieldValue.nowTimestamp()},
      merge: true,
    ));
  }

  // App went to background. Mark session paused (kept for resume).
  static Future<void> pause() {
    final id = SessionManager.pairedSessionId;
    if (id == null) return Future.value();
    return _queue.enqueue(PendingOp.set(
      '${FirestorePaths.pairedSessions}/$id',
      {
        'status': 'paused',
        'lastActiveAt': OfflineFieldValue.nowTimestamp(),
      },
      merge: true,
    ));
  }

  // App came back to foreground. Set status back to active.
  static Future<void> resume() {
    final id = SessionManager.pairedSessionId;
    if (id == null) return Future.value();
    return _queue.enqueue(PendingOp.set(
      '${FirestorePaths.pairedSessions}/$id',
      {
        'status': 'active',
        'lastActiveAt': OfflineFieldValue.nowTimestamp(),
      },
      merge: true,
    ));
  }

  // End the paired session, clear the phone pointer, and reset SessionManager.
  static Future<void> end() async {
    final id = SessionManager.pairedSessionId;
    final participantId = SessionManager.participantId;
    if (id == null) return;

    // Mark both copies ended in one batch.
    await _queue.enqueueBatch([
      PendingOp.set(
        '${FirestorePaths.pairedSessions}/$id',
        {
          'status': 'ended',
          'endedAt': OfflineFieldValue.nowTimestamp(),
          'lastActiveAt': OfflineFieldValue.nowTimestamp(),
        },
        merge: true,
      ),
      if (participantId != null)
        PendingOp.set(
          '${FirestorePaths.userData}/$participantId/'
          '${FirestorePaths.pairedSessions}/$id',
          {
            'status': 'ended',
            'endedAt': OfflineFieldValue.nowTimestamp(),
          },
          merge: true,
        ),
    ]);

    // Clear the stored id so we don't try to resume a finished session.
    try {
      await _storage.delete(key: activePairKey);
    } catch (e) {
      debugPrint('PairHooks: could not clear active-pair pointer - $e');
    }
    SessionManager.endPairedSession();
  }
}
