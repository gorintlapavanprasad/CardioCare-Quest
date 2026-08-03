import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

// GameLogHooks - saves "you finished a quest" records from games.
//
// Why not just use SurveyHooks? Surveys are questionnaires. A game quest isn't
// one, so we keep it out of the surveys collection to avoid confusing anyone
// looking at the data later. Everything is saved through OfflineQueue so it
// works offline.
abstract class GameLogHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  // Save one finished-quest record from a game.
  //
  // "data" is any extra game-specific stuff we just store as-is.
  // "pointsEarned" gets added to the user's points.
  // "countAsCompletion": if false, we DON'T bump the "completed" counter here -
  // the game host counts it once at the end instead. Use false for games that
  // save several times per play; leave the default when one call = one play.
  static Future<void> logQuestCompletion({
    required String uid,
    required String gameId,
    required String questId,
    int pointsEarned = 0,
    String? sessionId,
    Map<String, dynamic>? data,
    bool countAsCompletion = true,
  }) {
    if (uid.isEmpty) return Future.value();
    final eventId = _uuid.v4();
    final logId = _uuid.v4();

    final userUpdates = <String, dynamic>{};
    if (pointsEarned > 0) {
      userUpdates['points'] = OfflineFieldValue.increment(pointsEarned);
    }
    if (countAsCompletion) {
      userUpdates['surveysCompleted'] = OfflineFieldValue.increment(1);
      userUpdates['lastSurveyId'] = gameId;
      userUpdates['lastSurveyAt'] = OfflineFieldValue.nowTimestamp();
    }

    final ops = <PendingOp>[
      // 1. The quest record - a new doc each time, never overwrites old ones.
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/'
        '${FirestorePaths.gameLogs}/$logId',
        {
          'id': logId,
          'userId': uid,
          'gameId': gameId,
          'questId': questId,
          'pointsEarned': pointsEarned,
          if (sessionId != null) 'sessionId': sessionId,
          if (data != null) 'data': data,
          'countAsCompletion': countAsCompletion,
          'createdAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ];
    if (userUpdates.isNotEmpty) {
      // 2. The user's running totals - only if there's actually something to
      // add, so we don't send an empty, pointless update.
      ops.add(PendingOp.update(
          '${FirestorePaths.userData}/$uid', userUpdates));
    }
    // 3. Permanent event row (we never edit these).
    ops.add(PendingOp.set(
      '${FirestorePaths.events}/$eventId',
      {
        'id': eventId,
        'userId': uid,
        'event': 'game_quest_completed',
        'gameId': gameId,
        'questId': questId,
        'logId': logId,
        'pointsEarned': pointsEarned,
        if (sessionId != null) 'sessionId': sessionId,
        'countAsCompletion': countAsCompletion,
        'timestamp': OfflineFieldValue.nowTimestamp(),
        'syncedAt': OfflineFieldValue.nowTimestamp(),
      },
    ));
    return _queue.enqueueBatch(ops);
  }
}
