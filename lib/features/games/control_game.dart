import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

/// Daily Check-In — the **control game** condition for the comparison arm
/// of the study (work-plan goal #8). Same `TwineQuestionnaireHost` plumbing
/// any future survey-style Twine page can reuse: drop in an HTML file, wrap
/// it here, point the catalog at the wrapper.
///
/// Distinct from [DogQuestGame] in two ways:
///   * No GPS / movement tracking. The host is the lightweight
///     [TwineQuestionnaireHost] sibling, not the full [TwineGameHost].
///   * Submissions land in `surveys/control_daily_checkin/responses/{auto}`
///     via `SurveyHooks.submitResponse`, NOT in `Movement Data`.
class ControlGame extends StatelessWidget {
  const ControlGame({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'control_daily_checkin',
      title: 'Daily Check-In',
      htmlAsset: 'assets/game/control_game.html',
      // Token reward only — the control condition should not feel
      // gamified. Matches `pointsEarned` baked into the HTML's
      // CCQ.submitResponse payload.
      defaultPointsPerResponse: 10,
    );
  }
}
