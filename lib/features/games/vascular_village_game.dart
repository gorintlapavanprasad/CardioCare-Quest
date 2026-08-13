import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Vascular Village - 5-day story game set inside an artery wall. Your choices
// move the pressure, resources, and village health meters.

// Loads the Vascular Village HTML game.
class VascularVillageGame extends StatelessWidget {
  const VascularVillageGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Pass the game id, title, and HTML file to the host.
    return const TwineQuestionnaireHost(
      surveyId: 'vascular_village',
      title: 'Vascular Village',
      htmlAsset: 'assets/game/vascular_village.html',
    );
  }
}
