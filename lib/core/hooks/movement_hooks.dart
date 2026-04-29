import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

import '_geohash.dart';

/// Hook helpers for any GPS-tracked Twine game.
///
/// All writes go through [OfflineQueue] — durable to Hive first, replayed to
/// Firestore when online. Reads (`fetchOngoingState`, `fetchWeeklyQuestCount`)
/// fall back to Firestore's local cache when offline.
///
/// Conceptual flow for a movement game:
///   1. [generateSessionId] — make a session id when the player starts.
///   2. [pushPing] — every Nth GPS fix, write the location + ongoing state.
///   3. Either:
///        a. [endSession] — quest completed, increment user stats, write
///           CheckData, clear ongoing fields.
///        b. [saveOngoingState] — player exited mid-walk, just save the
///           progress so resume works next time.
///   4. [fetchOngoingState] on next app launch — restore mid-walk if any.
///
/// JS-bridge equivalent: the standard `START_TRACKING` / `FINISH_QUEST_DATA`
/// messages from a Twine page route into [TwineGameHost], which calls these
/// hooks under the hood.
abstract class MovementHooks {
  static OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  /// Mints a fresh session ID prefixed with the gameId. Stable across
  /// resumes once minted (the host stores it in `ongoingSessionId`).
  static String generateSessionId(String gameId) =>
      '${gameId}_${DateTime.now().millisecondsSinceEpoch}';

  /// Periodic GPS write. Called every N location fixes during gameplay.
  ///
  /// Writes 4 docs in one atomic batch so they all sync together:
  ///   * `Movement Data/{sessionId}` — session metadata (merge).
  ///   * `Movement Data/{sessionId}/LocationData/{auto}` — this ping.
  ///   * `data_points/{auto}` — geo-indexed copy for heatmaps.
  ///   * `userData/{uid}/gameStates/{gameId}` — ongoing-distance + path so
  ///     the next launch can resume mid-walk.
  ///
  /// Uses client-generated auto-IDs so OfflineQueue replay is deterministic
  /// (a queued batch always lands on the same docs even if many copies of
  /// the app are running for the same uid).
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
        .collection(FirestorePaths.movementData)
        .doc(sessionId)
        .collection(FirestorePaths.locationData)
        .doc()
        .id;
    final geoDocId =
        firestore.collection(FirestorePaths.dataPoints).doc().id;
    final geohash = geohashFor(position.latitude, position.longitude);

    return _queue.enqueueBatch([
      PendingOp.set(
        '${FirestorePaths.movementData}/$sessionId',
        {
          'sessionId': sessionId,
          'created': OfflineFieldValue.nowTimestamp(),
          'test': false,
          'userId': uid,
          'game': gameId,
        },
        merge: true,
      ),
      PendingOp.set(
        '${FirestorePaths.movementData}/$sessionId/'
        '${FirestorePaths.locationData}/$locationDocId',
        {
          'datetime': OfflineFieldValue.nowTimestamp(),
          'game': gameId,
          'geopoint':
              OfflineFieldValue.geopoint(position.latitude, position.longitude),
          'geohash': geohash,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'test': false,
        },
      ),
      PendingOp.set(
        '${FirestorePaths.dataPoints}/$geoDocId',
        {
          'location': {
            'geopoint': OfflineFieldValue.geopoint(
                position.latitude, position.longitude),
          },
          'userId': uid,
          'sessionId': sessionId,
          'game': gameId,
          'geohash': geohash,
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

  /// Quest completed. Increments lifetime user stats, writes the session
  /// completion doc + a CheckData entry, and clears the ongoing-walk fields
  /// from `gameStates/{gameId}`. All in one atomic batch.
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
          // Self-describing tombstone: the resume read in TwineGameHost
          // compares this against any leftover `ongoingSessionId`. If they
          // match, the doc's `ongoing*` fields are stale (race-condition
          // residue from a periodic write that landed after this delete)
          // and the resume is skipped.
          'lastCompletedSessionId': sessionId,
          'lastCompletedAt': OfflineFieldValue.nowTimestamp(),
        },
        merge: true,
      ),
    ]);
  }

  /// Save mid-walk progress so a subsequent app launch can resume. Used when
  /// the player explicitly exits with progress > 0.
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

  /// Persist the HTML's serialized `gameState` JSON blob (Twine state
  /// machine). Free-form payload — the host doesn't introspect it.
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

  /// Read the gameStates doc to decide whether to show "resume" or "start
  /// fresh" on app open. Returns the raw doc snapshot — caller validates the
  /// `ongoing*` fields strictly before treating them as in-progress (a doc
  /// with ongoingDistance: NaN is corrupt and should be ignored).
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

  /// Count completed quests of [gameId] for [uid] in the current ISO week
  /// (Monday 00:00 → now). Used by quest-catalog HUD displays.
  ///
  /// Single-field equality query so no composite index is needed; we filter
  /// `game` and `endedAt` client-side. Falls back to cache offline.
  static Future<int> fetchWeeklyQuestCount({
    required String uid,
    required String gameId,
  }) async {
    try {
      final now = DateTime.now();
      final startOfWeek = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday));

      final snap = await FirebaseFirestore.instance
          .collection(FirestorePaths.movementData)
          .where('userId', isEqualTo: uid)
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
