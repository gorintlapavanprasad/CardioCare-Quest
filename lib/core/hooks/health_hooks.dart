import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/health_service.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

// HealthHooks - saves a snapshot of watch/phone health data (heart rate, steps,
// etc. from Apple Watch / Wear OS) to the cloud.
//
// Why separate from the BP log: we only ask for BP once a day, but research
// wants vitals after EVERY game ends. So this runs on every game-end no matter
// what. Saves through OfflineQueue so it works offline and survives app close.
//
// Note: we always write a doc even when there's no watch data - it records
// "hasWearableData: false" so a game-end still counts and "no data" is clearly
// different from "no record at all".
abstract class HealthHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  // Grab the latest health snapshot and save it. Best-effort: if the watch
  // gives us nothing, we still save the doc (just with metadata) so the
  // game-end is countable.
  static Future<void> logSnapshot({
    required String uid,
    required String gameId,
    String? sessionId,
  }) async {
    if (uid.isEmpty) return;

    try {
      final snapshot = await HealthService.instance.captureSnapshot();

      // Drop the snapshot's own text date and use a proper timestamp instead,
      // so we can sort snapshots by time in the database.
      final snap = snapshot.toFirestore()..remove('collectedAt');

      final docId = _uuid.v4();
      await _queue.enqueue(PendingOp.set(
        '${FirestorePaths.userData}/$uid/healthSnapshots/$docId',
        {
          'id': docId,
          'userId': uid,
          'gameId': gameId,
          if (sessionId != null) 'sessionId': sessionId,
          'collectedAt': OfflineFieldValue.nowTimestamp(),
          'hasWearableData': snapshot.hasAnyData,
          ...snap,
        },
      ));
    } catch (e) {
      debugPrint('HealthHooks.logSnapshot error: $e');
    }
  }
}
