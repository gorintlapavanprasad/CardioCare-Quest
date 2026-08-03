import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Bingo Bash - a heart-health bingo board. The whole game is an HTML file;
// this class just loads it inside a plain (no-GPS) web view.
// Nothing is saved yet - quitting the game just sends you back home.

// Shows the Bingo Bash game by pointing the web-view host at its HTML file.
class BingoBashGame extends StatelessWidget {
  const BingoBashGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Hand the host the game's id, its title bar text, and which HTML to open.
    return const TwineQuestionnaireHost(
      surveyId: 'bingo_bash',
      title: 'Bingo Bash',
      htmlAsset: 'assets/game/bingo_bash.html',
    );
  }
}
