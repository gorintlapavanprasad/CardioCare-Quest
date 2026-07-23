import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';

/// Hook helpers for a paired co-play session (participant + caregiver).
///
/// A paired session groups every write made while the pair plays together.
/// [start] mints the session, writes the `pairedSessions/{id}` record (plus a
/// thin per-participant mirror), and registers it with [SessionManager] so the
/// telemetry layer stamps `pairedSessionId` onto every subsequent event.
///
/// All writes go through [OfflineQueue] — durable to Hive first, replayed to
/// Firestore when online — exactly like the other hooks, so a co-play session
/// survives airplane mode and app kill.
///
/// A pointer to the active session id is mirrored into secure storage so that
/// after a cold restart the app can offer to resume it (see
/// `PairResumeService`).
abstract class PairHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  /// Secure-storage key holding the active `pairedSessionId` across restarts.
  static const activePairKey = 'active_pair_session';
  static const _storage = FlutterSecureStorage();

  /// Start a paired session. Returns the new `pairedSessionId`.
  static Future<String> start({
    required String participantId,
    String? caregiverId,
    String? caregiverLabel,
    Map<String, dynamic>? settings,
    String? deviceTag,
  }) async {
    final id = SessionManager.startPairedSession(
      participantId: participantId,
      caregiverId: caregiverId,
      caregiverLabel: caregiverLabel,
    );

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
      'helpMarkerCount': 0,
    };

    await _queue.enqueueBatch([
      PendingOp.set('${FirestorePaths.pairedSessions}/$id', record, merge: true),
      // Thin mirror so a participant's sessions can be listed without a
      // collection-group query.
      PendingOp.set(
        '${FirestorePaths.userData}/$participantId/'
        '${FirestorePaths.pairedSessions}/$id',
        record,
        merge: true,
      ),
    ]);

    // Persist a resume pointer so a cold restart can reattach.
    try {
      await _storage.write(key: activePairKey, value: id);
    } catch (e) {
      debugPrint('PairHooks: could not persist active-pair pointer — $e');
    }
    return id;
  }

  /// Heartbeat — merge `lastActiveAt` so the cold-start resume logic knows the
  /// session was recently alive. Safe no-op when no session is active.
  static Future<void> touch() {
    final id = SessionManager.pairedSessionId;
    if (id == null) return Future.value();
    return _queue.enqueue(PendingOp.set(
      '${FirestorePaths.pairedSessions}/$id',
      {'lastActiveAt': OfflineFieldValue.nowTimestamp()},
      merge: true,
    ));
  }

  /// Mark the session paused (app backgrounded). Keeps the record resumable.
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

  /// Mark the session active again (app resumed).
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

  /// End the session. Writes the terminal status, then clears
  /// [SessionManager] paired state.
  static Future<void> end() async {
    final id = SessionManager.pairedSessionId;
    final participantId = SessionManager.participantId;
    if (id == null) return;
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
    try {
      await _storage.delete(key: activePairKey);
    } catch (e) {
      debugPrint('PairHooks: could not clear active-pair pointer — $e');
    }
    SessionManager.endPairedSession();
  }
}
