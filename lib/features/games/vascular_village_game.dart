import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Vascular Village - a 5-day story where you run a tiny village living inside
// an artery wall. Your choices move the "pressure", "resources", and
// "village health" meters. It's an HTML game, no GPS.

// Shows the Vascular Village game by loading its HTML in the web-view host.
class VascularVillageGame extends StatelessWidget {
  const VascularVillageGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Give the host the game id, title, and HTML file to open.
    return const TwineQuestionnaireHost(
      surveyId: 'vascular_village',
      title: 'Vascular Village',
      htmlAsset: 'assets/game/vascular_village.html',
    );
  }
}
