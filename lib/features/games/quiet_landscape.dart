import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Quiet Landscape - 16 slow breaths over a moving scene, then you enter
// your cuff reading. Saves on-device only; BP data isn't captured for research yet.

// Loads the Quiet Landscape HTML game.
class QuietLandscapeGame extends StatelessWidget {
  const QuietLandscapeGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Pass the game id, title, and HTML file to the host.
    return const TwineQuestionnaireHost(
      surveyId: 'quiet_landscape',
      title: 'Quiet Landscape',
      htmlAsset: 'assets/game/quiet_landscape.html',
    );
  }
}
