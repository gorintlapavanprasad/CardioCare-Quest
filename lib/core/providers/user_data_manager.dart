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

final GeoCollectionReference<Map<String, dynamic>> geoCollection =
    GeoCollectionReference(
      firestore.FirebaseFirestore.instance.collection(
        FirestorePaths.dataPoints,
      ),
    );

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

class UserDataProvider extends ChangeNotifier {
  Map<String, dynamic>? _userData;
  bool _isLoading = false;

  Map<String, dynamic>? get userData => _userData;
  bool get isLoading => _isLoading;

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

  Future<void> fetchUserData({String? participantId}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null && participantId == null) {
      debugPrint('No authenticated user and no participantId provided');
      _isLoading = false;
      notifyListeners();
      return;
    }

    final firestore = FirebaseFirestore.instance;
    DocumentSnapshot<Map<String, dynamic>>? doc;
    String sourceDescription = 'participantId';

    if (user != null) {
      sourceDescription = 'authUid';
      doc = await firestore
          .collection(FirestorePaths.userData)
          .doc(user.uid)
          .get();
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
        if (user != null) {
          await GetIt.instance<OfflineQueue>().enqueue(PendingOp.set(
            '${FirestorePaths.userData}/${doc.id}',
            {'authUid': user.uid},
            merge: true,
          ));
        }
        debugPrint('Data loaded successfully for document: ${doc.id}');
      } else if (user != null) {
        debugPrint(
          'No userData document found for UID: ${user.uid}, creating one...',
        );
        await createUserDocument(user);
        // Recursively fetch to load the newly created document
        await fetchUserData(participantId: participantId);
      } else {
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

  void clearData() {
    _userData = null;
    notifyListeners();
    debugPrint('User data cleared');
  }
}
