import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Post-Play Survey - short feedback form shown after playing.
// Loads an HTML file; the shared host handles everything.
class PostPlaySurveyScreen extends StatelessWidget {
  const PostPlaySurveyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'post_play_v1',
      title: 'How was your experience?',
      // The HTML page with the questions to show.
      htmlAsset: 'assets/game/post_play_survey.html',
    );
  }
}
