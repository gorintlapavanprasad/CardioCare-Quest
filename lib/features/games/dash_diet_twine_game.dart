import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

/// DASH Diet Game — food-card quiz + meal-builder authored as a
/// SugarCube Twee story. Distinct from `dash_diet_game/diet_log_screen.dart`
/// which is the dashboard's meal LOGGER. This one is the game catalog
/// entry that exercises hypertension-relevant food knowledge.
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
