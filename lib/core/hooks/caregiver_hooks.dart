import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';
import 'package:cardio_care_quest/core/hooks/telemetry_hooks.dart';

/// Hook helpers for the caregiver view of a paired session.
///
/// [markHelp] records that the caregiver assisted at a particular game moment;
/// [addNote] appends a free-text observation. Both write under the active
/// `pairedSessions/{id}` record and also emit a telemetry event (auto-stamped
/// with `pairedSessionId`) so markers appear in the top-level `events` stream
/// researchers already query.
abstract class CaregiverHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  /// Record a "help given" marker, attached to the current game/step context
  /// if a game is reporting one.
  static Future<void> markHelp({
    String helpType = 'other',
    String? note,
  }) async {
    final pairedSessionId = SessionManager.pairedSessionId;
    if (pairedSessionId == null) return;
    final markerId = _uuid.v4();
    final marker = <String, dynamic>{
      'markerId': markerId,
      'pairedSessionId': pairedSessionId,
      'participantId': SessionManager.participantId,
      'gameId': SessionManager.currentGame,
      'gameStep': SessionManager.currentStep,
      'helpType': helpType,
      if (note != null && note.isNotEmpty) 'note': note,
      'createdAt': OfflineFieldValue.nowTimestamp(),
    };

    await _queue.enqueueBatch([
      PendingOp.set(
        '${FirestorePaths.pairedSessions}/$pairedSessionId/'
        '${FirestorePaths.helpMarkers}/$markerId',
        marker,
      ),
      PendingOp.set(
        '${FirestorePaths.pairedSessions}/$pairedSessionId',
        {'helpMarkerCount': OfflineFieldValue.increment(1)},
        merge: true,
      ),
    ]);

    TelemetryHooks.logEvent(
      'caregiver_help_marked',
      parameters: {
        'gameId': SessionManager.currentGame,
        'gameStep': SessionManager.currentStep,
        'helpType': helpType,
      },
      userId: SessionManager.participantId,
    );
  }

  /// Append a caregiver note (one doc per entry — never overwritten).
  static Future<void> addNote(String text) async {
    final pairedSessionId = SessionManager.pairedSessionId;
    if (pairedSessionId == null || text.trim().isEmpty) return;
    final noteId = _uuid.v4();
    await _queue.enqueue(PendingOp.set(
      '${FirestorePaths.pairedSessions}/$pairedSessionId/'
      '${FirestorePaths.notes}/$noteId',
      {
        'noteId': noteId,
        'pairedSessionId': pairedSessionId,
        'participantId': SessionManager.participantId,
        'text': text.trim(),
        'gameId': SessionManager.currentGame,
        'createdAt': OfflineFieldValue.nowTimestamp(),
      },
    ));
  }
}
