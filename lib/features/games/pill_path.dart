import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Pill Path - tap the pill you took each day; a 7-day path fills in.
// Progress saves on-device only (not the cloud yet).

// Loads the Pill Path HTML game.
class PillPathGame extends StatelessWidget {
  const PillPathGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Pass the game id, title, and HTML file to the host.
    return const TwineQuestionnaireHost(
      surveyId: 'pill_path',
      title: 'Pill Path',
      htmlAsset: 'assets/game/pill_path.html',
    );
  }
}
