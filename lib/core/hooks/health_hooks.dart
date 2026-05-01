import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/health_service.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

/// Hook helpers that persist HealthKit / Health Connect snapshots
/// (Apple Watch / Wear OS data) to Firestore.
///
/// Why this is separate from [DailyLogHooks.logBP]:
/// the manual BP prompt is gated to once-per-day per participant for UX
/// reasons, but research requires a vitals snapshot **after every game
/// ends**, not just on days a BP reading is logged. Decoupling lets the
/// host fire `logSnapshot` on every game-end regardless of whether the
/// BP prompt was suppressed by the daily gate.
///
/// Storage:
///   userData/{uid}/healthSnapshots/{auto}
///
/// Each doc carries:
///   * `userId`, `gameId`, `sessionId?` — context for the snapshot
///   * `collectedAt` — server-side queryable Timestamp
///   * `hasWearableData` — true if any vitals field is present, false
///     when the user has no Watch / denied permission. Always present so
///     researchers can count game-ends and distinguish "no data" from
///     "no record".
///   * `heartRate?`, `restingHeartRate?`, `heartRateVariability?`,
///     `stepsToday?`, `activeEnergyToday?`, `exerciseMinutesToday?`,
///     `bloodOxygen?` — only set when the wearable reported them.
///
/// All writes go through [OfflineQueue] — durable across app kill +
/// offline.
abstract class HealthHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  /// Capture a snapshot from [HealthService] and persist it. Best-effort
  /// throughout — if the wearable returns nothing, the doc is still
  /// written with metadata so the game-end is countable.
  static Future<void> logSnapshot({
    required String uid,
    required String gameId,
    String? sessionId,
  }) async {
    if (uid.isEmpty) return;

    try {
      final snapshot = await HealthService.instance.captureSnapshot();

      // toFirestore() includes its own ISO `collectedAt`. Drop it — we
      // overwrite with an OfflineFieldValue Timestamp so Firestore
      // queries can use `orderBy('collectedAt')` natively.
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
