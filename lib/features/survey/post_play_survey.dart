import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

/// Post-Play Survey — work-plan goal #9. Five-question feedback
/// instrument authored in Twee (`assets/survey/survey.twee`) and rendered
/// through the same `ccq_twee.js` runtime used by the catalog games.
///
/// Submissions land in `surveys/post_play_v1/responses/{auto}` via
/// [SurveyHooks.submitResponse] (handled inside the survey HTML's
/// `submitSurvey()` function which calls `CCQ.submitResponse(...)`).
///
/// Reachable from the bottom of the dashboard's Home tab — see
/// `home_tab.dart`. Lives under `lib/features/survey/` so it doesn't get
/// confused with anything in `lib/features/games/`.
class PostPlaySurveyScreen extends StatelessWidget {
  const PostPlaySurveyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'post_play_v1',
      title: 'How was your experience?',
      // Rendered HTML lives next to the runtime so relative <script src>
      // resolves cleanly. Authoring source stays at assets/survey/survey.twee.
      htmlAsset: 'assets/game/post_play_survey.html',
      // 25 points awarded by the survey HTML's CCQ.submitResponse call;
      // setting the host default to 25 here as well so an offline /
      // bridge-call-fails fallback still records the right amount.
      defaultPointsPerResponse: 25,
    );
  }
}
