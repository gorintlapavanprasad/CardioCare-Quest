import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';
import 'package:cardio_care_quest/core/hooks/telemetry_hooks.dart';

// CaregiverHooks - records caregiver actions during a paired session.
// markHelp saves an "I helped" marker; addNote saves a text note.
// Both also fire a telemetry event so they appear in the research events stream.
abstract class CaregiverHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  // Save an "I helped" marker tagged to the current game step.
  static Future<void> markHelp({
    String helpType = 'other',
    String? note,
  }) async {
    // No paired session? Nothing to tag the marker to.
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

    // Save the marker and bump the session's help count in one batch.
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

    // Also log it as a telemetry event.
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

  // Save a caregiver's text note. Each call creates a new doc, never overwrites.
  static Future<void> addNote(String text) async {
    // Skip if no session is running or the text is empty.
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
