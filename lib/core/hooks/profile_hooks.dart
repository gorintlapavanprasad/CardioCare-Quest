import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

/// Helpers that mutate `userData/{uid}` profile fields. All writes go through
/// [OfflineQueue] so they survive offline + app kill.
///
/// JS-bridge equivalent: the standard `SET_DOG_NAME` bridge message is
/// translated into [updateBuddyName] by `TwineGameHost`.
abstract class ProfileHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  /// Update both `dogName` and `buddyName` aliases on the user profile.
  /// Some games refer to the player's companion as "dog", others as "buddy";
  /// we keep both keys in sync so any downstream view works.
  static Future<void> updateBuddyName(String uid, String name) {
    if (uid.isEmpty) return Future.value();
    return _queue.enqueue(PendingOp.update(
      '${FirestorePaths.userData}/$uid',
      {'dogName': name, 'buddyName': name},
    ));
  }

  /// Generic profile field overwrite. Use for one-off field updates that
  /// don't have a dedicated hook.
  static Future<void> setFields(
    String uid,
    Map<String, dynamic> values, {
    bool merge = true,
  }) {
    if (uid.isEmpty) return Future.value();
    return _queue.enqueue(PendingOp.set(
      '${FirestorePaths.userData}/$uid',
      values,
      merge: merge,
    ));
  }
}
