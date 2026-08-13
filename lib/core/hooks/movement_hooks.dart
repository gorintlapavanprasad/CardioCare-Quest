import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

import '_geohash.dart';

// MovementHooks - saves data for walking games that track your GPS location.
//
// Everything saves through OfflineQueue (works offline). Reads fall back to
// the phone's local cache when there's no internet.
//
// How a walking game uses these, start to finish:
//   1. generateSessionId - make an id when the walk starts.
//   2. pushPing - every so often, save where you are + how far you've gone.
//   3. Either endSession (walk finished) or saveOngoingState (quit part-way).
//   4. fetchOngoingState - next app open, check for an unfinished walk to resume.
abstract class MovementHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();
  static const _uuid = Uuid();

  // Make a fresh session id, tagged with the game name and the current time.
  // Stays the same across resumes once created.
  static String generateSessionId(String gameId) =>
      '${gameId}_${DateTime.now().millisecondsSinceEpoch}';

  // Save a GPS "ping" - called every few location updates while walking.
  //
  // Writes 4 docs together (all save or none):
  //   * the session's info, * this exact location point,
  //   * a copy for the map heatmap, and * the "walk in progress" state so we
  //     can pick up where you left off next time.
  //
  // We make the doc ids ourselves so that if a saved batch replays later, it
  // always lands on the same docs (no accidental duplicates).
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
          // Keep the running distance on the session as we go, so even a walk
          // the user quits early still shows real distance (not 0).
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
          // Distance-so-far on each point too, so anyone reading the location
          // points can see distance without digging elsewhere.
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

  // Walk finished. In one batch: bump the user's lifetime stats, save the
  // "completed" session doc + a checkpoint entry, and clear the "in progress"
  // fields so we don't try to resume a walk that's already done.
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
          // Remember which session we just finished. On next launch, if a
          // leftover "in progress" walk has this same id, we know it's stale
          // (a late GPS save that landed after we cleared things) and skip
          // resuming it.
          'lastCompletedSessionId': sessionId,
          'lastCompletedAt': OfflineFieldValue.nowTimestamp(),
        },
        merge: true,
      ),
      // A top-level "events" row, like every other finish writes. Without it,
      // finished walks wouldn't show up in the Community Stats (which only
      // reads the top-level events), so exercise numbers would sit at 0 even
      // while people are walking. Same shape as other completion events.
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

  // Save a half-finished walk so the next app open can resume it. Used when
  // the player quits with some distance already walked.
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

  // Save the game's own saved-state text (a blob from the Twine game). We just
  // store it as-is and don't look inside it.
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

  // Read the saved walk state to decide "resume" vs "start fresh" on app open.
  // Returns the raw doc - the caller checks the fields carefully first (a
  // broken/garbage value should be ignored, not resumed).
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

  // Count how many walks of this game the user finished this week (since
  // Monday). Shown on quest screens.
  //
  // Reads the participant's own movement sessions (now nested under
  // userData/{uid}/movementData), then filters by game and date here on the
  // phone - that way we don't need a special database index. Uses cache offline.
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
