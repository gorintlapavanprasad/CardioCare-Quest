import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Daily Check-In - a plain "how was your day" survey. It's the boring
// "control" game the study compares the fun games against.
// Just a few questions in an HTML page, no GPS. Answers get saved as
// survey responses.

// Shows the Daily Check-In survey by loading its HTML in the web-view host.
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
