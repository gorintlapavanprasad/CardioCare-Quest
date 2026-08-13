import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Salt Sludge - 5-day food-choice story. Pick potassium-rich foods to clear
// the artery "sludge", or salty foods to add more.

// Loads the Salt Sludge HTML game.
class SaltSludgeGame extends StatelessWidget {
  const SaltSludgeGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Pass the game id, title, and HTML file to the host.
    return const TwineQuestionnaireHost(
      surveyId: 'salt_sludge',
      title: 'Salt Sludge',
      htmlAsset: 'assets/game/salt_sludge.html',
    );
  }
}
