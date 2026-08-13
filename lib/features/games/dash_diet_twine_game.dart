import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Loads the DASH Diet Game HTML in the web-view host.
// The separate diet_log_screen.dart is the meal diary (not this game).
class DashDietTwineGame extends StatelessWidget {
  const DashDietTwineGame({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'dash_diet_game',
      title: 'DASH Diet Game',
      htmlAsset: 'assets/game/dash_diet_game.html',
    );
  }
}
