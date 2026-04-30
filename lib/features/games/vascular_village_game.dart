import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

/// Vascular Village — five-day decision narrative authored as a
/// SugarCube Twee story. Player governs a microscopic village inside an
/// artery wall; choices nudge the pressure / resources / village-health
/// counters tracked by the in-page Twee runtime.
class VascularVillageGame extends StatelessWidget {
  const VascularVillageGame({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'vascular_village',
      title: 'Vascular Village',
      htmlAsset: 'assets/game/vascular_village.html',
    );
  }
}
