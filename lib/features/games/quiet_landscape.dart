import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Quiet Landscape - a calm breathing scene, then you type in your blood
// pressure. You take 16 slow breaths over a moving landscape, then enter
// your cuff reading. It's an HTML game, no GPS.
// Right now the reading is only saved on the phone (not the cloud), so it's
// calming for the user but the research data isn't captured yet.

// Shows the Quiet Landscape game by loading its HTML in the web-view host.
class QuietLandscapeGame extends StatelessWidget {
  const QuietLandscapeGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Give the host the game id, title, and HTML file to open.
    return const TwineQuestionnaireHost(
      surveyId: 'quiet_landscape',
      title: 'Quiet Landscape',
      htmlAsset: 'assets/game/quiet_landscape.html',
    );
  }
}
