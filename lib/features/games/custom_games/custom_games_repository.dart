// CustomGamesRepository - the save/load helper for user-built games.
//
// Reading is live: the dashboard updates on its own whenever a game is
// added or finished. Saving goes through OfflineQueue (saved on the
// phone first, sent to the cloud later), so it works with no internet.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/services/offline_queue.dart';
import 'custom_game.dart';

// One shared helper for the whole app (a "singleton").
class CustomGamesRepository {
  CustomGamesRepository._();
  static final CustomGamesRepository instance = CustomGamesRepository._();

  static const _uuid = Uuid();
  OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  // Where this user's games live in the cloud.
  String _collectionPath(String uid) =>
      '${FirestorePaths.userData}/$uid/${FirestorePaths.customGames}';

  // Where one single game lives.
  String _docPath(String uid, String gameId) =>
      '${_collectionPath(uid)}/$gameId';

  // Live list of this user's games, newest first. Updates on its own.
  Stream<List<CustomGame>> watch(String uid) {
    if (uid.isEmpty) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection(_collectionPath(uid))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(CustomGame.fromDoc).toList());
  }

  // Save a brand-new game. Returns its new id. Only waits for the
  // phone-side save; the cloud sync happens on its own after.
  Future<String> create({
    required String uid,
    required CustomGame draft,
  }) async {
    if (uid.isEmpty) {
      throw StateError('CustomGamesRepository.create: uid is empty');
    }
    // Use the given id, or make a fresh random one.
    final id = draft.id.isNotEmpty ? draft.id : _uuid.v4();
    final game = CustomGame(
      id: id,
      title: draft.title,
      description: draft.description,
      category: draft.category,
      pointsReward: draft.pointsReward,
      // Copy the walk/quiz-specific fields from the draft. (A bug once
      // dropped these on save, so every game came out as an empty quiz.)
      gameType: draft.gameType,
      questions: draft.questions,
      prompt: draft.prompt,
      options: draft.options,
      targetDistance: draft.targetDistance,
      // Leave the "created" time null here; the cloud fills in the real
      // time when the save actually goes through.
      createdAt: null,
      completedCount: 0,
      lastCompletedAt: null,
    );
    final data = game.toMap();
    // Use the queue's own "now" marker for the created time (the plain
    // cloud one can't be stored on the phone while offline).
    data['createdAt'] = OfflineFieldValue.nowTimestamp();

    await _queue.enqueue(PendingOp.set(_docPath(uid, id), data, merge: true));
    return id;
  }

  // Mark that the game was finished one more time. Adds 1 to the "done"
  // count and saves the time. Points are handled elsewhere, not here.
  Future<void> markCompleted({
    required String uid,
    required String gameId,
  }) async {
    if (uid.isEmpty || gameId.isEmpty) return;
    await _queue.enqueue(PendingOp.update(_docPath(uid, gameId), {
      'completedCount': OfflineFieldValue.increment(1),
      'lastCompletedAt': OfflineFieldValue.nowTimestamp(),
    }));
  }

  // Delete a game for good. The dashboard drops its card on its own.
  Future<void> delete({
    required String uid,
    required String gameId,
  }) async {
    if (uid.isEmpty || gameId.isEmpty) return;
    await _queue.enqueue(PendingOp.delete(_docPath(uid, gameId)));
  }
}
