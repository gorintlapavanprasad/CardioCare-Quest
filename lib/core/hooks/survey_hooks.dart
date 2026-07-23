import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';

// SurveyHooks - saves answers from surveys / questionnaires (post-play survey,
// baseline survey, daily check-in, etc.). Everything saves through OfflineQueue
// so it works offline.
abstract class SurveyHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  // Save one completed questionnaire.
  //
  // "answers" is just a map of question → answer, stored as-is.
  // "pointsEarned" gets added to the user's points.
  // "countAsCompletion" (default true): if true, also bump the "surveys done"
  // counter. Set false for games that submit several times per play, so one
  // play only counts once (the game host adds the single count at the end).
  // "respondent": who actually answered - the participant by default, or a
  // caregiver if they're sharing the device.
  //
  // If a paired (two-person) session is running, its id is added automatically
  // so this answer links back to that session.
  static Future<void> submitResponse({
    required String uid,
    required String surveyId,
    required Map<String, dynamic> answers,
    int pointsEarned = 0,
    bool countAsCompletion = true,
    String? respondent,
  }) {
    if (uid.isEmpty) return Future.value();
    final eventId = _uuid.v4();
    final responseId = _uuid.v4();
    final effectiveRespondent = respondent ?? uid;
    final pairedSessionId = SessionManager.pairedSessionId;

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
      // 1. The answer itself - a new doc each time, never overwrites old ones.
      PendingOp.set(
        '${FirestorePaths.surveys}/$surveyId/'
        '${FirestorePaths.responses}/$responseId',
        {
          'id': responseId,
          'userId': uid,
          'respondent': effectiveRespondent,
          if (pairedSessionId != null) 'pairedSessionId': pairedSessionId,
          'surveyId': surveyId,
          'answers': answers,
          'pointsEarned': pointsEarned,
          'countAsCompletion': countAsCompletion,
          'submittedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ];
    if (userUpdates.isNotEmpty) {
      // 2. The user's running totals - only if there's something to add, so we
      // don't send an empty, pointless update.
      ops.add(PendingOp.update(
          '${FirestorePaths.userData}/$uid', userUpdates));
    }
    // 3. Permanent event row (we never edit these).
    ops.add(PendingOp.set(
      '${FirestorePaths.events}/$eventId',
      {
        'id': eventId,
        'userId': uid,
        'respondent': effectiveRespondent,
        if (pairedSessionId != null) 'pairedSessionId': pairedSessionId,
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
    // 4. The survey's own doc. Without this the survey shows up "empty" in the
    // database console (just a folder of answers, no real doc). Merge-save so
    // the first answer creates it and each later one bumps the count + time.
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
