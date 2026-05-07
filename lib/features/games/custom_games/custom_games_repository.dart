// CustomGamesRepository — data layer for participant-created goals.
//
// Reads stream live from Firestore (so the dashboard rebuilds instantly
// when a new game is created or completed). Writes go through
// OfflineQueue using the same set/update/delete pattern as the rest of
// the app, so creating or completing a custom game while offline still
// works — the queue replays once connectivity returns.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/services/offline_queue.dart';
import 'custom_game.dart';

class CustomGamesRepository {
  CustomGamesRepository._();
  static final CustomGamesRepository instance = CustomGamesRepository._();

  static const _uuid = Uuid();
  OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  /// Path of the customGames sub-collection under a participant doc.
  String _collectionPath(String uid) =>
      '${FirestorePaths.userData}/$uid/${FirestorePaths.customGames}';

  String _docPath(String uid, String gameId) =>
      '${_collectionPath(uid)}/$gameId';

  /// Live stream of the participant's custom games, newest first.
  Stream<List<CustomGame>> watch(String uid) {
    if (uid.isEmpty) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection(_collectionPath(uid))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(CustomGame.fromDoc).toList());
  }

  /// Create a new custom game. Returns the generated id so the caller
  /// can confirm + telemetry. Blocking only on the local Hive queue
  /// write; the Firestore round-trip is fire-and-forget.
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
      pointsReward: draft.pointsReward,
      // Type-specific fields propagated from the draft. Earlier this
      // function constructed `game` without them, which silently
      // dropped the participant's walk/quiz selection, target
      // distance, prompt, and answer options on every save — every
      // game ended up looking like a question-less quiz.
      gameType: draft.gameType,
      questions: draft.questions,
      prompt: draft.prompt,
      options: draft.options,
      targetDistance: draft.targetDistance,
      // server-side timestamp via OfflineFieldValue so it lands as
      // FieldValue.serverTimestamp() when the queue replays.
      createdAt: null,
      completedCount: 0,
      lastCompletedAt: null,
    );
    final data = game.toMap();
    // Replace the FieldValue.serverTimestamp() (un-serialisable across
    // Hive) with the queue's wire format.
    data['createdAt'] = OfflineFieldValue.nowTimestamp();

    await _queue.enqueue(PendingOp.set(_docPath(uid, id), data, merge: true));
    return id;
  }

  /// Mark the game as completed once. Bumps the completion counter +
  /// stamps lastCompletedAt. Caller should also award points via
  /// PointsHooks and fire telemetry — this method only owns the
  /// per-game doc.
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

  /// Permanently delete a custom game. The collection's StreamBuilder
  /// drops the card on the next snapshot so the dashboard updates with
  /// no manual refresh.
  Future<void> delete({
    required String uid,
    required String gameId,
  }) async {
    if (uid.isEmpty || gameId.isEmpty) return;
    await _queue.enqueue(PendingOp.delete(_docPath(uid, gameId)));
  }
}
