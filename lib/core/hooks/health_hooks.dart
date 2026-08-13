import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/health_service.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

// HealthHooks - saves a health data snapshot (heart rate, steps, etc.) after
// each game ends. Separate from the BP log because we only ask for BP once a day
// but research wants vitals after every game. Always saves a doc even with no
// watch data, so "no data" is clearly different from "no record at all".
abstract class HealthHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  // Grab the latest health snapshot and save it. If the watch has nothing,
  // we still save the doc so the game-end is counted.
  static Future<void> logSnapshot({
    required String uid,
    required String gameId,
    String? sessionId,
  }) async {
    if (uid.isEmpty) return;

    try {
      final snapshot = await HealthService.instance.captureSnapshot();

      // Remove the text date from the snapshot; we add a real timestamp below.
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
