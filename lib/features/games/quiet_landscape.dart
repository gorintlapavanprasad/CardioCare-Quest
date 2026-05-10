import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

/// Quiet Landscape — guided breathing + BP-capture experience
/// authored as a SugarCube Twee story (`assets/game-src/
/// quiet_landscape.tw`). The participant follows a 16-breath
/// landscape animation, then enters their cuff reading on the BP
/// Entry passage; the result is persisted to the same
/// `quietMinute_history` localStorage key Quiet Minute uses, so
/// Vascular Village's BP-zone display picks it up identically.
/// Uses [TwineQuestionnaireHost] — no GPS, no movement.
///
/// Future iteration: add a `CCQ.logBP(sys, dia, mood)` call inside
/// the `Save Reading` passage so the reading also reaches
/// `DailyLogHooks.logBP` and Firestore. Right now the reading lives
/// only in localStorage; participants get the calming UX but the
/// research signal isn't captured.
class QuietLandscapeGame extends StatelessWidget {
  const QuietLandscapeGame({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'quiet_landscape',
      title: 'Quiet Landscape',
      htmlAsset: 'assets/game/quiet_landscape.html',
    );
  }
}
