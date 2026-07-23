import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Salt Sludge - a 5-day food-choice story. Each day you pick one of two foods:
// potassium-rich foods clear the "sludge" in your artery, salty foods add more.
// It's an HTML game, no GPS.

// Shows the Salt Sludge game by loading its HTML in the web-view host.
class SaltSludgeGame extends StatelessWidget {
  const SaltSludgeGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Give the host the game id, title, and HTML file to open.
    return const TwineQuestionnaireHost(
      surveyId: 'salt_sludge',
      title: 'Salt Sludge',
      htmlAsset: 'assets/game/salt_sludge.html',
    );
  }
}
