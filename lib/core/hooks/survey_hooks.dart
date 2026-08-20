import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';

// SurveyHooks - saves survey/questionnaire answers. Works offline.
abstract class SurveyHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  // Save a completed survey.
  // "countAsCompletion" false: don't bump the counter (for games that submit
  // multiple times per play; the host counts once at the end).
  // "respondent": who answered. Defaults to the participant.
  // If a paired session is running, its id is added automatically.
  static Future<void> submitResponse({
    required String uid,
    required String surveyId,
    required Map<String, dynamic> answers,
    bool countAsCompletion = true,
    String? respondent,
  }) {
    if (uid.isEmpty) return Future.value();
    final eventId = _uuid.v4();
    final responseId = _uuid.v4();
    final effectiveRespondent = respondent ?? uid;
    final pairedSessionId = SessionManager.pairedSessionId;

    final userUpdates = <String, dynamic>{};
    if (countAsCompletion) {
      userUpdates['surveysCompleted'] = OfflineFieldValue.increment(1);
      userUpdates['lastSurveyId'] = surveyId;
      userUpdates['lastSurveyAt'] = OfflineFieldValue.nowTimestamp();
    }

    final ops = <PendingOp>[
      // 1. Answer doc (new each time).
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
          'countAsCompletion': countAsCompletion,
          'submittedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ];
    if (userUpdates.isNotEmpty) {
      // 2. User totals (only if there's something to update).
      ops.add(PendingOp.update(
          '${FirestorePaths.userData}/$uid', userUpdates));
    }
    // 3. Permanent event row.
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
        'questionCount': answers.length,
        'countAsCompletion': countAsCompletion,
        'timestamp': OfflineFieldValue.nowTimestamp(),
        'syncedAt': OfflineFieldValue.nowTimestamp(),
      },
    ));
    // 4. Survey summary doc. Without this the survey has no doc in the console,
    // just a folder of answers. First call creates it; later calls bump the count.
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
