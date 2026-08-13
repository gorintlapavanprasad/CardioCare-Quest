import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Blood Pressure Log (was "Quiet Minute"). Two minutes of breathing, then
// you enter your cuff reading, which saves to the cloud for the study.
// The old "quiet_minute" survey ID is kept so existing data still matches.
// Hidden from the catalog to stop casual play from polluting the research data.

// Loads the Blood Pressure Log HTML game.
class QuietMinuteGame extends StatelessWidget {
  const QuietMinuteGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Use the old slug so data from previous versions still lines up.
    return const TwineQuestionnaireHost(
      surveyId: 'quiet_minute',
      title: 'Blood Pressure Log',
      htmlAsset: 'assets/game/quiet_minute.html',
    );
  }
}
