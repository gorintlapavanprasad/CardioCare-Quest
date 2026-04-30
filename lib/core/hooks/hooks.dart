/// CardioCare Quest hooks library.
///
/// Single import for all hook helpers used by Twine games and feature
/// screens. Documentation lives in each individual file and in
/// `lib/core/hooks/README.md`.
///
/// Usage:
///   import 'package:cardio_care_quest/core/hooks/hooks.dart';
///   await DailyLogHooks.logBP(uid: '...', systolic: 120, diastolic: 80, mood: 3);
library;

export 'daily_log_hooks.dart';
export 'movement_hooks.dart';
export 'points_hooks.dart';
export 'profile_hooks.dart';
export 'survey_hooks.dart';
export 'telemetry_hooks.dart';
