import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:cardio_care_quest/core/providers/user_data_manager.dart';

/// Optimistic local-state mutations on the [UserDataProvider] backing the
/// dashboard. Use these whenever you've just queued a write through
/// [OfflineQueue] and want the UI to reflect the change immediately, instead
/// of waiting (potentially 10+ seconds offline) for Firestore's
/// `serverAndCache` `.get()` to time out and fall back to cache.
///
/// Eventual consistency: a future [UserDataProvider.fetchUserData] call
/// reconciles the local map against the actual server-resolved values once
/// the queue has drained.
///
/// JS-bridge equivalent: none — these are Flutter-only helpers. Twine games
/// call [pushPointsAwarded] indirectly via `TwineGameHost`'s end-game flow.
abstract class PointsHooks {
  /// Bump scalar counters (e.g. `points`, `totalSessions`, `measurementsTaken`)
  /// in the in-memory user-data map and notify listeners. Pass the **delta**,
  /// not the new total.
  ///
  /// Example:
  ///   PointsHooks.applyIncrements(context, {'points': 50, 'totalSessions': 1});
  static void applyIncrements(
    BuildContext context,
    Map<String, num> increments,
  ) {
    Provider.of<UserDataProvider>(context, listen: false)
        .applyLocalIncrements(increments);
  }

  /// Overwrite scalar fields (e.g. `lastSystolic`, `lastBPLogDate`) in the
  /// in-memory user-data map and notify listeners. Use for "most recent X"
  /// fields where the new value replaces the old one entirely.
  static void applySets(
    BuildContext context,
    Map<String, dynamic> values,
  ) {
    Provider.of<UserDataProvider>(context, listen: false)
        .applyLocalSets(values);
  }
}
