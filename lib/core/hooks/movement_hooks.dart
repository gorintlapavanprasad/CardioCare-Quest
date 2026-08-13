import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

import '_geohash.dart';

// MovementHooks - saves GPS data for walking games. Works offline.
//
// Typical flow:
//   1. generateSessionId - create an id when the walk starts.
//   2. pushPing - save location + distance every few updates.
//   3. endSession (finished) or saveOngoingState (quit early).
//   4. fetchOngoingState - on next open, check for an unfinished walk.
abstract class MovementHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  // Create a session id (game name + timestamp). Stays the same if resumed.
  static String generateSessionId(String gameId) =>
      '${gameId}_${DateTime.now().millisecondsSinceEpoch}';

  // Save a GPS ping during a walk. Writes 4 docs in one batch: session info,
  // this location point, a heatmap copy, and the "in progress" state.
  // Doc ids are generated here so replayed batches don't create duplicates.
  static Future<void> pushPing({
    required String uid,
    required String sessionId,
    required String gameId,
    required Position position,
    required double distanceWalked,
    required double targetDistance,
    required List<GeoPoint> pathCoordinates,
  }) {
    final firestore = FirebaseFirestore.instance;
    final locationDocId = firestore
        .collection(FirestorePaths.userData)
        .doc(uid)
        .collection(FirestorePaths.movementData)
        .doc(sessionId)
        .collection(FirestorePaths.locationData)
        .doc()
        .id;
    final geoDocId =
        firestore.collection(FirestorePaths.movementPoints).doc().id;
    final geohash = geohashFor(position.latitude, position.longitude);

    return _queue.enqueueBatch([
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/'
        '${FirestorePaths.movementData}/$sessionId',
        {
          'sessionId': sessionId,
          'created': OfflineFieldValue.nowTimestamp(),
          'test': false,
          'userId': uid,
          'game': gameId,
          // Running distance so a walk quit early still shows real distance.
          'runningDistance': distanceWalked,
          'targetDistance': targetDistance,
        },
        merge: true,
      ),
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/'
        '${FirestorePaths.movementData}/$sessionId/'
        '${FirestorePaths.locationData}/$locationDocId',
        {
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'game': gameId,
          'geopoint':
              OfflineFieldValue.geopoint(position.latitude, position.longitude),
          'geohash': geohash,
          'latitude': position.latitude,
          'longitude': position.longitude,
          // Distance on each point so readers don't have to look elsewhere.
          'distanceWalked': distanceWalked,
          'targetDistance': targetDistance,
          'test': false,
        },
      ),
      PendingOp.set(
        '${FirestorePaths.movementPoints}/$geoDocId',
        {
          'location': {
            'geopoint': OfflineFieldValue.geopoint(
                position.latitude, position.longitude),
          },
          'userId': uid,
          'sessionId': sessionId,
          'game': gameId,
          'geohash': geohash,
          'distanceWalked': distanceWalked,
          'timestamp': OfflineFieldValue.nowTimestamp(),
        },
      ),
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/'
        '${FirestorePaths.gameStates}/$gameId',
        {
          'ongoingDistance': distanceWalked,
          'ongoingTarget': targetDistance,
          'ongoingSessionId': sessionId,
          'ongoingPath': pathCoordinates
              .map((c) => OfflineFieldValue.geopoint(c.latitude, c.longitude))
              .toList(),
        },
        merge: true,
      ),
    ]);
  }

  // Walk finished. Saves stats, marks the session completed, adds a checkpoint,
  // and clears the "in progress" fields so we don't try to resume it later.
  static Future<void> endSession({
    required String uid,
    required String sessionId,
    required String gameId,
    required double distanceWalked,
    required double targetDistance,
    required int pointsEarned,
    required String buddyName,
    required List<GeoPoint> pathCoordinates,
    String? completionEventName,
  }) {
    final firestore = FirebaseFirestore.instance;
    final checkDocId = firestore
        .collection(FirestorePaths.userData)
        .doc(uid)
        .collection(FirestorePaths.movementData)
        .doc(sessionId)
        .collection(FirestorePaths.checkData)
        .doc()
        .id;
    final lastLat =
        pathCoordinates.isNotEmpty ? pathCoordinates.last.latitude : null;
    final lastLng =
        pathCoordinates.isNotEmpty ? pathCoordinates.last.longitude : null;

    return _queue.enqueueBatch([
      PendingOp.update('${FirestorePaths.userData}/$uid', {
        'points': OfflineFieldValue.increment(pointsEarned),
        'totalDistance': OfflineFieldValue.increment(distanceWalked.toInt()),
        'totalSessions': OfflineFieldValue.increment(1),
        'distanceTraveled':
            OfflineFieldValue.increment(distanceWalked.toInt()),
        'measurementsTaken': OfflineFieldValue.increment(1),
        'lastPlayedAt': OfflineFieldValue.nowTimestamp(),
      }),
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/'
        '${FirestorePaths.movementData}/$sessionId',
        {
          'sessionId': sessionId,
          'created': OfflineFieldValue.nowTimestamp(),
          'test': false,
          'game': gameId,
          'gameType': gameId,
          'targetQuest': '${targetDistance.toInt()}m',
          'totalDistance': distanceWalked,
          'dogName': buddyName,
          'buddyName': buddyName,
          'endedAt': OfflineFieldValue.nowTimestamp(),
          'pointsEarned': pointsEarned,
        },
        merge: true,
      ),
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/'
        '${FirestorePaths.movementData}/$sessionId/'
        '${FirestorePaths.checkData}/$checkDocId',
        {
          'event': completionEventName ?? '${gameId}_completed',
          'latitude': lastLat,
          'longitude': lastLng,
          'sessionID': sessionId,
          'sessionId': sessionId,
          'downloadSpeed': 0,
          'uploadSpeed': 0,
          'latency': 0,
          'timestamp': OfflineFieldValue.nowTimestamp(),
        },
      ),
      PendingOp.set(
        '${FirestorePaths.userData}/$uid/'
        '${FirestorePaths.gameStates}/$gameId',
        {
          'ongoingDistance': OfflineFieldValue.delete(),
          'ongoingTarget': OfflineFieldValue.delete(),
          'ongoingSessionId': OfflineFieldValue.delete(),
          'ongoingPath': OfflineFieldValue.delete(),
          // Remember the finished session id. On next launch, if we see an
          // "in progress" walk with this id we know it's a stale GPS write
          // and can skip resuming it.
          'lastCompletedSessionId': sessionId,
          'lastCompletedAt': OfflineFieldValue.nowTimestamp(),
        },
        merge: true,
      ),
      // Top-level events row. Without this, Community Stats wouldn't count
      // the walk and exercise numbers would show 0.
      PendingOp.set(
        '${FirestorePaths.events}/${_uuid.v4()}',
        {
          'id': sessionId,
          'userId': uid,
          'event': 'game_quest_completed',
          'gameId': gameId,
          'questId': completionEventName ?? '${gameId}_completed',
          'sessionId': sessionId,
          'pointsEarned': pointsEarned,
          'distanceWalked': distanceWalked,
          'targetDistance': targetDistance,
          'countAsCompletion': true,
          'timestamp': OfflineFieldValue.nowTimestamp(),
          'syncedAt': OfflineFieldValue.nowTimestamp(),
        },
      ),
    ]);
  }

  // Save the current walk state so it can be resumed next app open.
  static Future<void> saveOngoingState({
    required String uid,
    required String gameId,
    required String sessionId,
    required double distanceWalked,
    required double targetDistance,
    required List<GeoPoint> pathCoordinates,
  }) {
    if (uid.isEmpty) return Future.value();
    return _queue.enqueue(PendingOp.set(
      '${FirestorePaths.userData}/$uid/'
      '${FirestorePaths.gameStates}/$gameId',
      {
        'ongoingDistance': distanceWalked,
        'ongoingTarget': targetDistance,
        'ongoingSessionId': sessionId,
        'ongoingPath': pathCoordinates
            .map((c) => OfflineFieldValue.geopoint(c.latitude, c.longitude))
            .toList(),
      },
      merge: true,
    ));
  }

  // Save the Twine game's state blob. Stored as-is, not parsed.
  static Future<void> saveGameStateJson({
    required String uid,
    required String gameId,
    required String stateJson,
  }) {
    if (uid.isEmpty) return Future.value();
    return _queue.enqueue(PendingOp.set(
      '${FirestorePaths.userData}/$uid/'
      '${FirestorePaths.gameStates}/$gameId',
      {'gameState': stateJson},
      merge: true,
    ));
  }

  // Read saved walk state. Returns the raw doc; caller decides resume vs. fresh start.
  static Future<DocumentSnapshot<Map<String, dynamic>>> fetchOngoingState({
    required String uid,
    required String gameId,
  }) {
    return FirebaseFirestore.instance
        .collection(FirestorePaths.userData)
        .doc(uid)
        .collection(FirestorePaths.gameStates)
        .doc(gameId)
        .get();
  }

  // Count completed walks for this game since Monday. Shown on quest screens.
  // Filters by game and date on the phone to avoid needing a database index.
  static Future<int> fetchWeeklyQuestCount({
    required String uid,
    required String gameId,
  }) async {
    try {
      final now = DateTime.now();
      final startOfWeek = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday));

      final snap = await FirebaseFirestore.instance
          .collection(FirestorePaths.userData)
          .doc(uid)
          .collection(FirestorePaths.movementData)
          .get();

      var count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['game'] != gameId) continue;
        final endedAt = data['endedAt'];
        if (endedAt is! Timestamp) continue;
        if (endedAt.toDate().isBefore(startOfWeek)) continue;
        count++;
      }
      return count;
    } catch (e) {
      debugPrint('MovementHooks.fetchWeeklyQuestCount error: $e');
      return 0;
    }
  }
}
