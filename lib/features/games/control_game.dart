import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Daily Check-In - the control condition for the study. A few plain questions
// in HTML. Intentionally simple so the fun games can be compared against it.
class ControlGame extends StatelessWidget {
  const ControlGame({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'control_daily_checkin',
      title: 'Daily Check-In',
      htmlAsset: 'assets/game/control_game.html',
      // Give only a tiny 10 points - this one isn't meant to feel like a game.
      defaultPointsPerResponse: 10,
    );
  }
}
