import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

/// Hook helpers for survey / questionnaire response storage.
///
/// Used by the control-game Twine page (`assets/game/control_game.html`)
/// and any other questionnaire-style content (post-play survey, baseline
/// survey, etc.). Mirrors the existing `surveys/{surveyId}/responses/{uid}`
/// schema implied by [FirestorePaths.surveys] / [FirestorePaths.responses].
///
/// Storage shape:
///   surveys/{surveyId}/responses/{auto}            — one row per submission
///   userData/{uid}                                 — lifetime counters
///   events/{eventUuid}                             — immutable event row
///
/// All writes batch atomically through OfflineQueue.
abstract class SurveyHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  /// Persist a single completed questionnaire submission.
  ///
  /// `answers` is a free-form map of `{questionId: answer}` recorded
  /// verbatim — answer values may be int (Likert), bool, or string.
  /// `pointsEarned` is added to `userData/{uid}.points`.
  static Future<void> submitResponse({
    required String uid,
    required String surveyId,
    required Map<String, dynamic> answers,
    int pointsEarned = 0,
  }) {
    if (uid.isEmpty) return Future.value();
    final eventId = _uuid.v4();
    final responseId = _uuid.v4();

    return _queue.enqueueBatch([
      // 1. Per-response doc — never overwrites prior submissions.
      PendingOp.set(
        '${FirestorePaths.surveys}/$surveyId/'
        '${FirestorePaths.responses}/$responseId',
        {
          'id': responseId,
          'userId': uid,
          'surveyId': surveyId,
          'answers': answers,
          'pointsEarned': pointsEarned,
          'submittedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
      // 2. Lifetime user counters.
      PendingOp.update('${FirestorePaths.userData}/$uid', {
        if (pointsEarned > 0)
          'points': OfflineFieldValue.increment(pointsEarned),
        'surveysCompleted': OfflineFieldValue.increment(1),
        'lastSurveyId': surveyId,
        'lastSurveyAt': OfflineFieldValue.nowTimestamp(),
      }),
      // 3. Immutable event row.
      PendingOp.set(
        '${FirestorePaths.events}/$eventId',
        {
          'id': eventId,
          'userId': uid,
          'event': 'survey_response_submitted',
          'surveyId': surveyId,
          'responseId': responseId,
          'pointsEarned': pointsEarned,
          'questionCount': answers.length,
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'syncedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ]);
  }
}
