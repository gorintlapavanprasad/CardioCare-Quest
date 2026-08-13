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

// user_data_manager - holds the logged-in user's profile in memory.
// Loads from Firestore, keeps it in memory, exposes points/name/etc to the app.

// ---- DATA MODELS ----

// Summary of one play session.
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

// Cloud collection of map points, searchable by location.
final GeoCollectionReference<Map<String, dynamic>> geoCollection =
    GeoCollectionReference(
      firestore.FirebaseFirestore.instance.collection(
        FirestorePaths.movementPoints,
      ),
    );

// Live stream of map points within radiusKm of center. Updates automatically.
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

// One map spot with network readings (speed, latency) and the game played there.
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

  // Build from a Firestore doc. Missing fields fall back to safe defaults.
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

// Keeps the current user's data in memory. Notifies the UI on changes.
// Screens read points/name/etc. from here instead of querying the cloud.
class UserDataProvider extends ChangeNotifier {
  Map<String, dynamic>? _userData; // the user's full record, or null if not loaded.
  bool _isLoading = false; // true while a fetch is running.

  Map<String, dynamic>? get userData => _userData;
  bool get isLoading => _isLoading;

  // Who is answering this session ("client" or caregiver). Set on the
  // "who's playing?" prompt after login. Resets each launch so a shared device
  // always re-asks. Cleared on logout.
  String? _respondent;
  String? get respondent => _respondent;
  set respondent(String? value) {
    _respondent = value;
    notifyListeners();
  }

  // Convenience getters with safe defaults. Some accept old field names too.
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

  // Bump number fields (e.g. +50 points) in memory right away so the dashboard
  // updates instantly. The cloud write is already queued; this just makes it
  // visible now. Real values reconcile on the next fetchUserData.
  void applyLocalIncrements(Map<String, num> increments) {
    if (_userData == null) return;
    for (final entry in increments.entries) {
      final current = (_userData![entry.key] as num?) ?? 0;
      _userData![entry.key] = current + entry.value;
    }
    notifyListeners();
  }

  // Overwrite fields (e.g. "last BP") in memory so the dashboard shows them now.
  void applyLocalSets(Map<String, dynamic> values) {
    if (_userData == null) return;
    _userData!.addAll(values);
    notifyListeners();
  }

  // Load the user's record from the cloud. Looks up by signed-in account or
  // participantId. Wipes old data first when switching users so the previous
  // participant's data can't leak into the new session (bug found 2026-05-10).
  // Re-fetching the SAME user keeps the cached data visible to avoid flickering.
  Future<void> fetchUserData({String? participantId}) async {
    final currentLoadedPid =
        (_userData?['participantId'] ?? _userData?['uid']) as String?;
    // Different person than what's loaded?
    final isUserSwitch = participantId != null &&
        currentLoadedPid != null &&
        currentLoadedPid != participantId;
    if (isUserSwitch) {
      _userData = null; // clear old person's data so it can't leak into the new one.
      _isLoading = true;
      notifyListeners();
    }

    final user = FirebaseAuth.instance.currentUser;
    // No account and no participantId? Nothing to load.
    if (user == null && participantId == null) {
      debugPrint('No authenticated user and no participantId provided');
      _isLoading = false;
      notifyListeners();
      return;
    }

    final firestore = FirebaseFirestore.instance;
    DocumentSnapshot<Map<String, dynamic>>? doc;
    String sourceDescription = 'participantId';

    // Try to find the doc by auth uid first.
    if (user != null) {
      sourceDescription = 'authUid';
      doc = await firestore
          .collection(FirestorePaths.userData)
          .doc(user.uid)
          .get();
      // Not found by id? Search by authUid field.
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

    // Still nothing? Try by participantId.
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
        _userData = doc.data() as Map<String, dynamic>;
        // Stamp the auth uid so we can find this doc quickly next time.
        if (user != null) {
          await GetIt.instance<OfflineQueue>().enqueue(PendingOp.set(
            '${FirestorePaths.userData}/${doc.id}',
            {'authUid': user.uid},
            merge: true,
          ));
        }
        debugPrint('Data loaded successfully for document: ${doc.id}');
      } else if (user != null) {
        // No doc yet. Create one, then reload.
        debugPrint(
          'No userData document found for UID: ${user.uid}, creating one...',
        );
        await createUserDocument(user);
        // Reload to get the doc we just created.
        await fetchUserData(participantId: participantId);
      } else {
        // No account and no doc. Use a bare-bones placeholder to avoid crashes.
        debugPrint('No user data found for participantId: $participantId');
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
      // Fetch failed (maybe offline). Use safe defaults.
      debugPrint('Error fetching user data: $e');
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

  // Create a fresh user record with zero/default values on first sign-in.
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

  // Clear user data on logout or when switching participants.
  void clearData() {
    _userData = null;
    _respondent = null;
    notifyListeners();
    debugPrint('User data cleared');
  }
}
