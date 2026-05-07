import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

/// Hook helpers for per-action activity logs from hub-and-spoke games
/// (Vascular Village's per-quest credits, future hub-style games).
///
/// Why this is separate from [SurveyHooks]: surveys are questionnaire
/// submissions (post-play survey, baseline survey, daily check-in).
/// A game's quest completion isn't a questionnaire — even if the data
/// shape happens to fit. Routing game activity through SurveyHooks
/// pollutes the `surveys/` collection with non-survey records and
/// misleads any researcher querying it.
///
/// Storage shape:
///   userData/{uid}/gameLogs/{auto}    — one doc per quest play
///   userData/{uid}                    — points + completion bumps
///   events/{auto}                     — immutable event row
///
/// All writes batch atomically through OfflineQueue.
abstract class GameLogHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  /// Persist a single per-quest completion record from a game.
  ///
  /// `data` is a free-form map of quest-specific context (e.g. the
  /// heart-quality rating from Pump the Heart) — captured verbatim
  /// for downstream behaviour-pattern analysis.
  ///
  /// `pointsEarned` is added to `userData/{uid}.points`.
  ///
  /// `countAsCompletion` mirrors [SurveyHooks.submitResponse]: when
  /// false, the user-level `surveysCompleted` counter is NOT bumped
  /// here — the host's `_performExit` does it once at session end
  /// instead. Set false for partial-progress submits (Vascular
  /// Village's per-quest pattern); leave default for one-shot
  /// completions where each call IS one full play.
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
      // 1. Per-quest log doc — never overwrites prior records.
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
      // 2. Lifetime user counters — only when there's something to
      // bump. A partial submit with 0 points and
      // `countAsCompletion: false` would otherwise enqueue an empty
      // update.
      ops.add(PendingOp.update(
          '${FirestorePaths.userData}/$uid', userUpdates));
    }
    // 3. Immutable event row.
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
