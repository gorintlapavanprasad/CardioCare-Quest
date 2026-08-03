import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

// user_data_manager - holds the logged-in person's profile and game data.
//
// Loads the user's record from the cloud (Firestore), keeps it in memory, and
// lets the rest of the app read points/name/etc. It also has a few small data
// classes for map points and past play sessions.

// ---- DATA MODELS ----

// One play session's summary (date, game, points, distance, etc.).
class SessionData {
  final DateTime date;
  final String game;
  final int? pointsCollected;
  final int? distanceTraveled;
  final double? averageUploadSpeed;
  final double? averageDownloadSpeed;
  final double? radiusGyration;
  List<dynamic>? sessionDataPoints;

  SessionData({
    required this.date,
    required this.game,
    this.pointsCollected,
    this.distanceTraveled,
    this.sessionDataPoints,
    this.averageDownloadSpeed,
    this.averageUploadSpeed,
    this.radiusGyration,
  });
}

// A cloud collection of map data points that we can search by location.
final GeoCollectionReference<Map<String, dynamic>> geoCollection =
    GeoCollectionReference(
      firestore.FirebaseFirestore.instance.collection(
        FirestorePaths.dataPoints,
      ),
    );

// Live feed of map points within radiusKm of a center spot. Updates on its own
// as points are added/moved nearby.
Stream<List<firestore.DocumentSnapshot>> getPointsStream(
  LatLng center,
  double radiusKm,
) {
  return geoCollection.subscribeWithin(
    center: GeoFirePoint(firestore.GeoPoint(center.latitude, center.longitude)),
    radiusInKm: radiusKm,
    field: 'location.geopoint',
    geopointFrom: (data) {
      final location = data['location'] as Map<String, dynamic>;
      return location['geopoint'] as firestore.GeoPoint;
    },
  );
}

// One spot on the map with its network readings (speed, latency) and the game
// that was being played there.
class DataPoint {
  final LatLng point;
  final DateTime timestamp;
  final double uploadSpeed;
  final double downloadSpeed;
  final double latency;
  final String gamePlayed;

  DataPoint({
    required this.point,
    required this.timestamp,
    required this.uploadSpeed,
    required this.downloadSpeed,
    required this.latency,
    required this.gamePlayed,
  });

  // Build a DataPoint from a cloud record. Uses safe fallbacks (0, "Unknown",
  // now) so a missing field won't crash us.
  factory DataPoint.fromFirestore(firestore.DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final location = data['location'] as Map<String, dynamic>? ?? {};
    final firestore.GeoPoint geoPoint =
        location['geopoint'] as firestore.GeoPoint;

    return DataPoint(
      point: LatLng(geoPoint.latitude, geoPoint.longitude),
      timestamp:
          ((data['timestamp'] ?? data['datetime']) as firestore.Timestamp?)
              ?.toDate() ??
          DateTime.now(),
      uploadSpeed: (data['uploadSpeed'] as num?)?.toDouble() ?? 0.0,
      downloadSpeed: (data['downloadSpeed'] as num?)?.toDouble() ?? 0.0,
      latency: (data['latency'] as num?)?.toDouble() ?? 0.0,
      gamePlayed:
          data['game'] as String? ?? data['gameType'] as String? ?? 'Unknown',
    );
  }
}

// ---- USER DATA PROVIDER ----

// Keeps the current user's data in memory and tells the UI to refresh when it
// changes (that's what ChangeNotifier does). Screens read points/name/etc. from
// here instead of hitting the cloud themselves.
class UserDataProvider extends ChangeNotifier {
  Map<String, dynamic>? _userData; // the user's full record, or null if not loaded.
  bool _isLoading = false; // true while a fetch is running.

  Map<String, dynamic>? get userData => _userData;
  bool get isLoading => _isLoading;

  // Who is physically answering this session - chosen in the "who's playing?"
  // prompt shown once after login. `null` until chosen. Used to tag survey
  // responses (SurveyHooks.submitResponse `respondent`) as the participant
  // ("client") or a caregiver helping them, without changing the signed-in
  // account. In-memory only: it resets each launch so a shared device always
  // re-asks. Cleared on logout via clearData().
  String? _respondent;
  String? get respondent => _respondent;
  set respondent(String? value) {
    _respondent = value;
    notifyListeners();
  }

  // Handy getters. Each falls back to a safe default if the field is missing,
  // and some accept either an old or new field name for backward compatibility.
  int get points => _userData?['points'] ?? 0;
  String get firstName => _userData?['basicInfo']?['firstName'] ?? 'Explorer';
  String get uid => _userData?['uid'] ?? '';
  String get phone => _userData?['phone'] ?? '1111111111';
  int get distanceTraveled =>
      _userData?['distanceTraveled'] ?? _userData?['totalDistance'] ?? 0;
  int get totalSessions =>
      _userData?['measurementsTaken'] ?? _userData?['totalSessions'] ?? 0;
  int get totalRadiusGyration =>
      _userData?['radGyration'] ?? _userData?['totalRadiusGyration'] ?? 0;
  List<dynamic> get dataPoints => _userData?['dataPoints'] ?? [];

  /// Apply optimistic increments to local userData WITHOUT touching Firestore.
  ///
  /// Used by log screens after [OfflineQueue.enqueueBatch] returns: the queue
  /// has already durably saved the write to Hive, but Firestore's local cache
  /// (which Provider reads from) hasn't seen the change yet. This nudges the
  /// in-memory map so the dashboard reflects the new points/counters
  /// immediately, instead of forcing the user to wait for a real `.get()`
  /// round-trip that hangs ~10 s offline.
  ///
  /// Eventually consistent: the next successful [fetchUserData] reconciles
  /// against the server-resolved values.
  // Bump some number fields (e.g. add 50 points) in memory right away, so the
  // dashboard updates instantly instead of waiting on the cloud.
  void applyLocalIncrements(Map<String, num> increments) {
    if (_userData == null) return;
    for (final entry in increments.entries) {
      final current = (_userData![entry.key] as num?) ?? 0;
      _userData![entry.key] = current + entry.value;
    }
    notifyListeners();
  }

  /// Apply optimistic field overwrites to local userData. Use for
  /// "last X" / "last Y" fields and any non-counter values you want the
  /// dashboard to show immediately after a log save.
  void applyLocalSets(Map<String, dynamic> values) {
    if (_userData == null) return;
    _userData!.addAll(values);
    notifyListeners();
  }

  // Load the user's record from the cloud into memory. Can look them up by the
  // signed-in account or by a participantId. Long comment below explains the
  // tricky "wipe first when switching users" bit.
  Future<void> fetchUserData({String? participantId}) async {
    // Wipe in-memory user data BEFORE the network round-trip so any
    // concurrent reader (the dashboard, the WebView host's `_uid`
    // getter, the GET_TODAY_BP bridge handler) sees `null` rather
    // than the previous participant's map during the fetch window.
    //
    // Without this, switching from participant A to participant B
    // leaks A's data into B's session for the duration of the
    // Firestore query: the WebView's user-agent stamp at TwineHost
    // initState time can read A's uid, the bridge's participant-
    // isolation check then thinks "same user, no wipe", and A's
    // `quietMinute_history` localStorage remains visible to B's
    // Vascular Village. The participant sees A's BP on B's village
    // welcome screen, which is exactly the leak we hit on
    // 2026-05-10.
    //
    // We only wipe when the caller is asking for a participant we
    // don't already have loaded - refetching the same participant
    // (e.g. after a BP submit, to refresh `lastSystolic`) keeps
    // the cached map visible during the round-trip so the UI
    // doesn't flicker to a loading state for in-place updates.
    final currentLoadedPid =
        (_userData?['participantId'] ?? _userData?['uid']) as String?;
    // Are we loading a *different* person than the one already in memory?
    final isUserSwitch = participantId != null &&
        currentLoadedPid != null &&
        currentLoadedPid != participantId;
    if (isUserSwitch) {
      _userData = null; // clear old person's data so it can't leak into the new one.
      _isLoading = true;
      notifyListeners();
    }

    final user = FirebaseAuth.instance.currentUser;
    // No signed-in account and no participant to look up? Nothing to do.
    if (user == null && participantId == null) {
      debugPrint('No authenticated user and no participantId provided');
      _isLoading = false;
      notifyListeners();
      return;
    }

    final firestore = FirebaseFirestore.instance;
    DocumentSnapshot<Map<String, dynamic>>? doc;
    String sourceDescription = 'participantId';

    // First try: find the doc by the signed-in account.
    if (user != null) {
      sourceDescription = 'authUid';
      doc = await firestore
          .collection(FirestorePaths.userData)
          .doc(user.uid)
          .get();
      // Not found by id? Try finding one tagged with this account instead.
      if (!doc.exists) {
        final query = await firestore
            .collection(FirestorePaths.userData)
            .where('authUid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          doc = query.docs.first;
        }
      }
    }

    // Still nothing? Fall back to looking up by participantId.
    if ((doc == null || !doc.exists) && participantId != null) {
      sourceDescription = 'participantId';
      final query = await firestore
          .collection(FirestorePaths.userData)
          .where('participantId', isEqualTo: participantId)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        doc = query.docs.first;
      }
    }

    debugPrint('Fetching data for user via $sourceDescription');

    _isLoading = true;
    notifyListeners();

    try {
      if (doc != null && doc.exists) {
        // Found it - keep the data.
        _userData = doc.data() as Map<String, dynamic>;
        // Stamp the account id onto the doc so next time we can find it fast.
        if (user != null) {
          await GetIt.instance<OfflineQueue>().enqueue(PendingOp.set(
            '${FirestorePaths.userData}/${doc.id}',
            {'authUid': user.uid},
            merge: true,
          ));
        }
        debugPrint('Data loaded successfully for document: ${doc.id}');
      } else if (user != null) {
        // Signed in but no doc yet - make one, then load it.
        debugPrint(
          'No userData document found for UID: ${user.uid}, creating one...',
        );
        await createUserDocument(user);
        // Recursively fetch to load the newly created document
        await fetchUserData(participantId: participantId);
      } else {
        // No account and no saved doc - use a bare-bones placeholder so the
        // app doesn't crash on missing data.
        debugPrint('No user data found for participantId: $participantId');
        // Create a minimal userData object to prevent null errors
        _userData = {
          'uid': participantId ?? 'unknown',
          'participantId': participantId,
          'basicInfo': {'firstName': 'Explorer'},
          'points': 0,
          'totalDistance': 0,
          'totalSessions': 0,
        };
      }
    } catch (e) {
      // Something went wrong (e.g. no internet) - fall back to safe defaults.
      debugPrint('Error fetching user data: $e');
      // Set a default user data object to prevent null pointer exceptions
      _userData = {
        'uid': user?.uid ?? participantId ?? 'unknown',
        'basicInfo': {'firstName': 'Explorer'},
        'points': 0,
        'totalDistance': 0,
        'totalSessions': 0,
      };
    }

    _isLoading = false;
    notifyListeners();
  }

  // Create a fresh user record with everything set to zero/defaults. Runs the
  // first time a new account signs in.
  Future<void> createUserDocument(User user) async {
    await GetIt.instance<OfflineQueue>().enqueue(PendingOp.set(
      '${FirestorePaths.userData}/${user.uid}',
      {
        'uid': user.uid,
        'email': user.email ?? 'guest_${user.uid.substring(0, 5)}@demo.com',
        'measurementsTaken': 0,
        'distanceTraveled': 0,
        'dataPoints': [],
        'radGyration': 0,
        'createdAt': OfflineFieldValue.nowTimestamp(),
        'totalSessions': 0,
        'totalSteps': 0,
        'totalDistance': 0,
        'points': 0,
        'basicInfo': {'firstName': 'Explorer'},
      },
      merge: true,
    ));

    debugPrint('User profile created in userData for UID: ${user.uid}');
  }

  // Forget the current user's data (used on logout / switching people).
  void clearData() {
    _userData = null;
    _respondent = null;
    notifyListeners();
    debugPrint('User data cleared');
  }
}
