import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:cardio_care_quest/core/providers/user_data_manager.dart';

// PointsHooks - updates the on-screen numbers (points, totals) right away.
//
// After you save something, use these so the dashboard changes instantly
// instead of waiting on the cloud (which can take 10+ seconds offline). It's
// just a quick local update - the real values get reloaded from the cloud later
// and take over.
abstract class PointsHooks {
  // Add to counters like points/totals shown on screen, and refresh the UI.
  // Pass the AMOUNT TO ADD (the change), not the new total.
  //
  // Example:
  //   PointsHooks.applyIncrements(context, {'points': 50, 'totalSessions': 1});
  static void applyIncrements(
    BuildContext context,
    Map<String, num> increments,
  ) {
    Provider.of<UserDataProvider>(context, listen: false)
        .applyLocalIncrements(increments);
  }

  // Replace fields shown on screen (like "last blood pressure") with new values
  // and refresh the UI. Use this for "most recent X" fields where the new value
  // fully replaces the old one.
  static void applySets(
    BuildContext context,
    Map<String, dynamic> values,
  ) {
    Provider.of<UserDataProvider>(context, listen: false)
        .applyLocalSets(values);
  }
}
