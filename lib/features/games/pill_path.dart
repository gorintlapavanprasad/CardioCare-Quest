import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

/// Pill Path — medication-adherence game authored as a SugarCube Twee
/// story (`assets/game-src/pill_path.tw`). The participant marks each
/// day's pills as taken (or caregiver-assisted) and watches a 7-day
/// "path" of adherence build up; completing a path triggers a
/// celebration scene before starting the next path. Pure narrative
/// game — no GPS, no movement — so it uses
/// [TwineQuestionnaireHost] like the other questionnaire-style Twee
/// games (Salt Sludge, Daily Check-In, etc.). The Twee runtime
/// persists state to localStorage (`pill_path_save`); future iterations
/// can call `CCQ.submitResponse` from inside `Mark Taken Helper` to
/// also push adherence records to Firestore via `SurveyHooks`.
class PillPathGame extends StatelessWidget {
  const PillPathGame({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'pill_path',
      title: 'Pill Path',
      htmlAsset: 'assets/game/pill_path.html',
    );
  }
}
