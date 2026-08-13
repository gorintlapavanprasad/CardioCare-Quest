import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

// ProfileHooks - updates fields on the user's profile. Works offline.
abstract class ProfileHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  // Set the companion name. Saves as both "dogName" and "buddyName" because
  // different games use different field names.
  static Future<void> updateBuddyName(String uid, String name) {
    if (uid.isEmpty) return Future.value();
    return _queue.enqueue(PendingOp.update(
      '${FirestorePaths.userData}/$uid',
      {'dogName': name, 'buddyName': name},
    ));
  }

  // Generic: set any profile fields not covered by the helpers above.
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
