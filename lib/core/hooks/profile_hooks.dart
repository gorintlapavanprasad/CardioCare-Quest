import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

// ProfileHooks - changes fields on the user's profile. Saves through
// OfflineQueue so changes work offline and survive the app closing.
abstract class ProfileHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  // Set the player's companion name. We save it under two names, "dogName" and
  // "buddyName", because some games say "dog" and others say "buddy" - keeping
  // both in sync means every screen shows the right thing.
  static Future<void> updateBuddyName(String uid, String name) {
    if (uid.isEmpty) return Future.value();
    return _queue.enqueue(PendingOp.update(
      '${FirestorePaths.userData}/$uid',
      {'dogName': name, 'buddyName': name},
    ));
  }

  // Set any profile fields you want. A catch-all for updates that don't have
  // their own dedicated helper above.
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
