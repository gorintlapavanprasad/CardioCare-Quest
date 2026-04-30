import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

/// Salt Sludge — five-day food-choice narrative authored as a SugarCube
/// Twee story (`assets/game/salt_sludge.twee`). The player picks one of
/// two foods each day; high-potassium choices clear the artery's "sludge"
/// counter, high-sodium choices add to it. Pure narrative game — no GPS,
/// no movement tracking. Uses [TwineQuestionnaireHost] for the same
/// reason the other Twee games do: the in-page `ccq_twee.js` runtime
/// drives state and navigation, the host just provides the WebView and
/// bridge.
class SaltSludgeGame extends StatelessWidget {
  const SaltSludgeGame({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'salt_sludge',
      title: 'Salt Sludge',
      htmlAsset: 'assets/game/salt_sludge.html',
    );
  }
}
