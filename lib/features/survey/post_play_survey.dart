import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Post-Play Survey - a short 5-question "how was it?" form shown after
// playing. The questions live in an HTML file; this screen just loads that
// file and lets the shared survey host do the work. Answers are saved and
// earn 25 points.

// The screen. It just hands the right settings to the shared survey host.
class PostPlaySurveyScreen extends StatelessWidget {
  const PostPlaySurveyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'post_play_v1',
      title: 'How was your experience?',
      // The HTML page with the questions to show.
      htmlAsset: 'assets/game/post_play_survey.html',
      // Points for finishing. Set here too so we still award the right
      // amount if the survey page can't report it (e.g. offline).
      defaultPointsPerResponse: 25,
    );
  }
}
