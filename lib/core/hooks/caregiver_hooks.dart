import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';
import 'package:cardio_care_quest/core/hooks/telemetry_hooks.dart';

// CaregiverHooks - for when a caregiver is helping during a two-person session.
//
// markHelp records "I helped here" at a game moment; addNote saves a free-text
// note. Both save under the current paired session and also fire a telemetry
// event, so these show up in the same events stream researchers already look at.
abstract class CaregiverHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  // Save an "I helped" marker, tagged with whatever game/step is happening now.
  static Future<void> markHelp({
    String helpType = 'other',
    String? note,
  }) async {
    // No paired session running? Nothing to attach a help marker to, so stop.
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

    // Save the marker and bump the session's help count, together.
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

    // Also log it as an event so it shows up in the research events stream.
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

  // Save a caregiver's free-text note (a new doc each time, never overwritten).
  static Future<void> addNote(String text) async {
    // Need a running session and some actual text, otherwise skip.
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
