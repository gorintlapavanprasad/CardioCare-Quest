import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_questionnaire_host.dart';

/// Blood Pressure Log — the relaxed-state BP capture game (formerly
/// shown to participants as "Quiet Minute"). The Dart class name and
/// Firestore `surveyId` keep the original `quiet_minute` slug so
/// historical telemetry / responses stay queryable; only the
/// user-visible title was renamed.
///
/// Two-minute breathing exercise → BP entry form (sys/dia inputs validated
/// 60-250 / 30-160) → Save. The Save passage calls `CCQ.logBP(...)` over
/// the bridge, which `TwineQuestionnaireHost` routes to
/// `DailyLogHooks.logBP` so the reading lands in
/// `userData/{uid}/dailyLogs/{today}/bpReadings/{auto}`.
///
/// Per the research protocol, this is the **only** participant-facing
/// path to log a BP reading — other games no longer prompt for BP. It's
/// hidden from the Game Catalog (`showInCatalog: false` in
/// game_stories.dart) and only reachable from the dashboard's latest-BP
/// card so casual play of the entry flow doesn't corrupt the dataset.
/// The HealthKit snapshot still fires on every game end via
/// `HealthHooks.logSnapshot`.
class QuietMinuteGame extends StatelessWidget {
  const QuietMinuteGame({super.key});

  @override
  Widget build(BuildContext context) {
    return const TwineQuestionnaireHost(
      surveyId: 'quiet_minute',
      title: 'Blood Pressure Log',
      htmlAsset: 'assets/game/quiet_minute.html',
    );
  }
}
