import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Pill Path - a "did you take your pills?" game. Each day you tap the pill
// you took (or mark that a caregiver helped), and a 7-day path fills in.
// Finish a week and a little celebration plays. It's an HTML game, no GPS.
// For now progress is only saved on the phone itself, not the cloud.

// Shows the Pill Path game by loading its HTML in the web-view host.
class PillPathGame extends StatelessWidget {
  const PillPathGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Give the host the game id, title, and HTML file to open.
    return const TwineQuestionnaireHost(
      surveyId: 'pill_path',
      title: 'Pill Path',
      htmlAsset: 'assets/game/pill_path.html',
    );
  }
}
