// Saves and loads user-built games. Reads are live (stream). Writes go
// through OfflineQueue so they work without internet.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/services/offline_queue.dart';
import 'custom_game.dart';

// Singleton.
class CustomGamesRepository {
  CustomGamesRepository._();
  static final CustomGamesRepository instance = CustomGamesRepository._();

  static const _uuid = Uuid();
  OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  String _collectionPath(String uid) =>
      '${FirestorePaths.userData}/$uid/${FirestorePaths.customGames}';

  String _docPath(String uid, String gameId) =>
      '${_collectionPath(uid)}/$gameId';

  // Live stream of the user's games, newest first.
  Stream<List<CustomGame>> watch(String uid) {
    if (uid.isEmpty) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection(_collectionPath(uid))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(CustomGame.fromDoc).toList());
  }

  // Save a new game and return its id. Cloud sync happens in the background.
  Future<String> create({
    required String uid,
    required CustomGame draft,
  }) async {
    if (uid.isEmpty) {
      throw StateError('CustomGamesRepository.create: uid is empty');
    }
    final id = draft.id.isNotEmpty ? draft.id : _uuid.v4();
    final game = CustomGame(
      id: id,
      title: draft.title,
      description: draft.description,
      category: draft.category,
      // A past bug dropped these on save (all games came out as empty quizzes).
      gameType: draft.gameType,
      questions: draft.questions,
      scenes: draft.scenes,
      prompt: draft.prompt,
      options: draft.options,
      targetDistance: draft.targetDistance,
      createdAt: null,
      completedCount: 0,
      lastCompletedAt: null,
    );
    final data = game.toMap();
    // Queue timestamp used because plain cloud timestamps can't be stored offline.
    data['createdAt'] = OfflineFieldValue.nowTimestamp();

    await _queue.enqueue(PendingOp.set(_docPath(uid, id), data, merge: true));
    return id;
  }

  // Increments the completion count and records the time. Points handled elsewhere.
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

  // Delete a game. The dashboard card disappears automatically.
  Future<void> delete({
    required String uid,
    required String gameId,
  }) async {
    if (uid.isEmpty || gameId.isEmpty) return;
    await _queue.enqueue(PendingOp.delete(_docPath(uid, gameId)));
  }
}
