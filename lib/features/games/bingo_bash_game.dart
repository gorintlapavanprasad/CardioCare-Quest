import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Loads the Bingo Bash HTML game in the web-view host (no GPS needed).
class BingoBashGame extends StatelessWidget {
  const BingoBashGame({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'bingo_bash',
      title: 'Bingo Bash',
      htmlAsset: 'assets/game/bingo_bash.html',
    );
  }
}
