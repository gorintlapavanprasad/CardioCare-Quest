import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

// GameLogHooks - saves "quest completed" records from games.
// Kept separate from SurveyHooks because a game quest is not a questionnaire.
// Saves through OfflineQueue so it works offline.
abstract class GameLogHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  // Save one finished-quest record.
  // "data": extra game-specific fields, stored as-is.
  // "countAsCompletion": false = don't bump the counter (use for games that call
  // this multiple times per play; the host counts once at the end instead).
  static Future<void> logQuestCompletion({
    required String uid,
    required String gameId,
    required String questId,
    String? sessionId,
    Map<String, dynamic>? data,
    bool countAsCompletion = true,
  }) {
    if (uid.isEmpty) return Future.value();
    final eventId = _uuid.v4();
    final logId = _uuid.v4();

    final userUpdates = <String, dynamic>{};
    if (countAsCompletion) {
      userUpdates['surveysCompleted'] = OfflineFieldValue.increment(1);
      userUpdates['lastSurveyId'] = gameId;
      userUpdates['lastSurveyAt'] = OfflineFieldValue.nowTimestamp();
    }

    final ops = <PendingOp>[
      // 1. Quest record (new doc every time).
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/'
        '${FirestorePaths.gameLogs}/$logId',
        {
          'id': logId,
          'userId': uid,
          'gameId': gameId,
          'questId': questId,
          if (sessionId != null) 'sessionId': sessionId,
          if (data != null) 'data': data,
          'countAsCompletion': countAsCompletion,
          'createdAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ];
    if (userUpdates.isNotEmpty) {
      // 2. User totals (only if there's something to add).
      ops.add(PendingOp.update(
          '${FirestorePaths.userData}/$uid', userUpdates));
    }
    // 3. Permanent event row.
    ops.add(PendingOp.set(
      '${FirestorePaths.events}/$eventId',
      {
        'id': eventId,
        'userId': uid,
        'event': 'game_quest_completed',
        'gameId': gameId,
        'questId': questId,
        'logId': logId,
        if (sessionId != null) 'sessionId': sessionId,
        'countAsCompletion': countAsCompletion,
        'timestamp': OfflineFieldValue.nowTimestamp(),
        'syncedAt': OfflineFieldValue.nowTimestamp(),
      },
    ));
    return _queue.enqueueBatch(ops);
  }
}
