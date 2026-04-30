import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

/// Bingo Bash — daily-activity bingo board authored as a SugarCube Twee
/// story. Uses [TwineQuestionnaireHost] purely as a non-GPS WebView host;
/// the in-page runtime (`ccq_twee.js`) drives state and navigation.
///
/// No data persistence at this stage — the story exits via the
/// "Central Hub" passage which the runtime intercepts to call
/// `CCQ.goHome()`. Hooking this into [DailyLogHooks] (e.g. recording
/// which cells the player marked) is a straightforward follow-up.
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
