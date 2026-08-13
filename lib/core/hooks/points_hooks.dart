import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:cardio_care_quest/core/providers/user_data_manager.dart';

// PointsHooks - updates on-screen numbers (points, totals) immediately.
// Use these after saving so the dashboard doesn't wait on the cloud.
// Cloud values reconcile on the next fetch.
abstract class PointsHooks {
  // Add to on-screen counters. Pass the amount to add, not the new total.
  // Example: PointsHooks.applyIncrements(context, {'points': 50});
  static void applyIncrements(
    BuildContext context,
    Map<String, num> increments,
  ) {
    Provider.of<UserDataProvider>(context, listen: false)
        .applyLocalIncrements(increments);
  }

  // Overwrite on-screen fields (e.g. "last blood pressure") with new values.
  // Use for "most recent X" fields where the new value replaces the old one.
  static void applySets(
    BuildContext context,
    Map<String, dynamic> values,
  ) {
    Provider.of<UserDataProvider>(context, listen: false)
        .applyLocalSets(values);
  }
}
