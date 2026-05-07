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
  ///
  /// `countAsCompletion` (default true): when true, this submit also
  /// bumps the user-level `surveysCompleted` counter and refreshes
  /// `lastSurveyId` / `lastSurveyAt`. Set to false for partial-
  /// progress submits — Vascular Village's per-quest credits use
  /// this so a single play producing 4–5 SUBMIT_RESPONSE calls only
  /// counts as one completion. The host (`TwineQuestionnaireHost.
  /// _performExit`) owns the once-per-session counter bump in that
  /// pattern.
  static Future<void> submitResponse({
    required String uid,
    required String surveyId,
    required Map<String, dynamic> answers,
    int pointsEarned = 0,
    bool countAsCompletion = true,
  }) {
    if (uid.isEmpty) return Future.value();
    final eventId = _uuid.v4();
    final responseId = _uuid.v4();

    final userUpdates = <String, dynamic>{};
    if (pointsEarned > 0) {
      userUpdates['points'] = OfflineFieldValue.increment(pointsEarned);
    }
    if (countAsCompletion) {
      userUpdates['surveysCompleted'] = OfflineFieldValue.increment(1);
      userUpdates['lastSurveyId'] = surveyId;
      userUpdates['lastSurveyAt'] = OfflineFieldValue.nowTimestamp();
    }

    final ops = <PendingOp>[
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
          'countAsCompletion': countAsCompletion,
          'submittedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ];
    if (userUpdates.isNotEmpty) {
      // 2. Lifetime user counters — only when there's something to
      // bump. A partial-progress submit with 0 points and
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
        'event': 'survey_response_submitted',
        'surveyId': surveyId,
        'responseId': responseId,
        'pointsEarned': pointsEarned,
        'questionCount': answers.length,
        'countAsCompletion': countAsCompletion,
        'timestamp': OfflineFieldValue.nowTimestamp(),
        'syncedAt': OfflineFieldValue.nowTimestamp(),
      },
    ));
    // 4. Parent survey doc — without this, `surveys/{surveyId}` shows
    // up in the Firestore console as a ghost (italic, no fields, only
    // a subcollection of responses below). Set-with-merge so the
    // first submit creates the doc and subsequent submits accumulate
    // the count + refresh the timestamp without clobbering anything
    // else written here later.
    ops.add(PendingOp.set(
      '${FirestorePaths.surveys}/$surveyId',
      {
        'surveyId': surveyId,
        'lastResponseAt': OfflineFieldValue.nowTimestamp(),
        'responseCount': OfflineFieldValue.increment(1),
      },
      merge: true,
    ));
    return _queue.enqueueBatch(ops);
  }
}
