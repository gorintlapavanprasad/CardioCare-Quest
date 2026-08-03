import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

// Blood Pressure Log - the real BP-entry game (used to be called
// "Quiet Minute"). Two minutes of breathing, then you type your cuff reading
// and it saves to the cloud for the study.
// The old "quiet_minute" id is kept so old data still matches up; only the
// name shown to users changed. This is the ONLY game that logs BP, and it's
// hidden from the catalog so people don't play it casually and mess up the data.

// Shows the Blood Pressure Log game by loading its HTML in the web-view host.
class QuietMinuteGame extends StatelessWidget {
  const QuietMinuteGame({super.key});

  @override
  Widget build(BuildContext context) {
    // Give the host the game id (kept as the old slug), title, and HTML file.
    return const TwineQuestionnaireHost(
      surveyId: 'quiet_minute',
      title: 'Blood Pressure Log',
      htmlAsset: 'assets/game/quiet_minute.html',
    );
  }
}
