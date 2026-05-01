import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

/// Quiet Minute — the relaxed-state BP capture game.
///
/// Two-minute breathing exercise → BP entry form (sys/dia inputs validated
/// 60-250 / 30-160) → Save. The Save passage calls `CCQ.logBP(...)` over
/// the bridge, which `TwineQuestionnaireHost` routes to
/// `DailyLogHooks.logBP` so the reading lands in
/// `userData/{uid}/dailyLogs/{today}/bpReadings/{auto}`.
///
/// Per the research protocol, this is the **only** participant-facing
/// path to log a BP reading — other games no longer prompt for BP. The
/// HealthKit snapshot still fires on every game end via
/// `HealthHooks.logSnapshot`.
class QuietMinuteGame extends StatelessWidget {
  const QuietMinuteGame({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'quiet_minute',
      title: 'Quiet Minute',
      htmlAsset: 'assets/game/quiet_minute.html',
    );
  }
}
