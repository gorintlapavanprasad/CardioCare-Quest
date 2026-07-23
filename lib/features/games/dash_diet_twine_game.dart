import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// DASH Diet Game - a food quiz + build-a-meal game about heart-healthy eating.
// It's an HTML game loaded in the web-view host.
// Note: this is the GAME. The separate diet_log_screen.dart is where you
// actually write down what you ate.

// Shows the DASH Diet game by loading its HTML in the web-view host.
class DashDietTwineGame extends StatelessWidget {
  const DashDietTwineGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Give the host the game id, title, and HTML file to open.
    return const TwineQuestionnaireHost(
      surveyId: 'dash_diet_game',
      title: 'DASH Diet Game',
      htmlAsset: 'assets/game/dash_diet_game.html',
    );
  }
}
