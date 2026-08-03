import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';

// PairHooks - a "two people playing together" session.
//
// When a participant plays with a caregiver, we make ONE session record. Every
// event/survey/walk saved after that gets tagged with the same session id (done
// automatically by TelemetryHooks), so later we can see the whole session as one.
//
// Writes go through OfflineQueue (saved on the phone first, sent to the cloud
// when there's internet), so this works offline too.
abstract class PairHooks {
  // The one shared write queue.
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  // We save the current session id on the phone. If the app is closed and
  // reopened, this is how we know a session was in progress and can resume it.
  static const activePairKey = 'active_pair_session';
  static const _storage = FlutterSecureStorage();

  // START a session. The joint-setup screen calls this. Returns the new id.
  static Future<String> start({
    required String participantId,
    String? caregiverId,
    String? caregiverLabel,
    Map<String, dynamic>? settings,
    String? deviceTag,
  }) async {
    // Mark the session active. From now on every event carries this id.
    final id = SessionManager.startPairedSession(
      participantId: participantId,
      caregiverId: caregiverId,
      caregiverLabel: caregiverLabel,
    );

    // The session record. "lastActiveAt" is a heartbeat - the last time we saw
    // it alive (used later to decide if it's still safe to resume).
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

    // Save it in two places at once (both save or neither).
    await _queue.enqueueBatch([
      // 1) Main copy, in the top-level pairedSessions collection.
      PendingOp.set('${FirestorePaths.pairedSessions}/$id', record, merge: true),
      // 2) A small copy under the participant, so listing "this person's
      //    sessions" is quick.
      PendingOp.set(
        '${FirestorePaths.userData}/$participantId/'
        '${FirestorePaths.pairedSessions}/$id',
        record,
        merge: true,
      ),
    ]);

    // Remember this session on the phone so a restart can find it. If storage
    // fails, just log it - not worth crashing over.
    try {
      await _storage.write(key: activePairKey, value: id);
    } catch (e) {
      debugPrint('PairHooks: could not persist active-pair pointer - $e');
    }
    return id;
  }

  // TOUCH - heartbeat. Bumps "lastActiveAt" to now. Does nothing if no session.
  static Future<void> touch() {
    final id = SessionManager.pairedSessionId;
    if (id == null) return Future.value();
    return _queue.enqueue(PendingOp.set(
      '${FirestorePaths.pairedSessions}/$id',
      {'lastActiveAt': OfflineFieldValue.nowTimestamp()},
      merge: true,
    ));
  }

  // PAUSE - app went to background. Mark "paused" but keep it so we can resume.
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

  // RESUME - app came back to the foreground. Flip status back to "active".
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

  // END - the pair is done. Mark "ended", clear the phone pointer, and tell
  // SessionManager to forget it (so later writes aren't tagged with this old id).
  static Future<void> end() async {
    final id = SessionManager.pairedSessionId;
    final participantId = SessionManager.participantId;
    if (id == null) return;

    // Mark both copies ended, together.
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

    // Forget the phone pointer so we don't try to resume a finished session.
    try {
      await _storage.delete(key: activePairKey);
    } catch (e) {
      debugPrint('PairHooks: could not clear active-pair pointer - $e');
    }
    SessionManager.endPairedSession();
  }
}
