import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

// ─── NETGAUGE CORE: Session & Telemetry Data ───
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
    this.radiusGyration
  });
}

// Radius-based stream for gathering points from firestore
final GeoCollectionReference<Map<String, dynamic>> geoCollection =
GeoCollectionReference(firestore.FirebaseFirestore.instance.collection('geo_points')); // Updated to match new top-level collection

Stream<List<firestore.DocumentSnapshot>> getPointsStream(LatLng center, double radiusKm) {
  return geoCollection.subscribeWithin(
    center: GeoFirePoint(firestore.GeoPoint(center.latitude, center.longitude)),
    radiusInKm: radiusKm,
    field: 'geopoint', // Updated to match new 'geopoint' field name
    geopointFrom: (data) => data['geopoint'] as firestore.GeoPoint,
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
    required this.gamePlayed
  });

  factory DataPoint.fromFirestore(firestore.DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final firestore.GeoPoint geoPoint = data['geopoint'] as firestore.GeoPoint;

    return DataPoint(
      point: LatLng(geoPoint.latitude, geoPoint.longitude),
      timestamp: (data['timestamp'] as firestore.Timestamp).toDate(),
      uploadSpeed: (data['uploadSpeed'] as num?)?.toDouble() ?? 0.0,
      downloadSpeed: (data['downloadSpeed'] as num?)?.toDouble() ?? 0.0,
      latency: (data['latency'] as num?)?.toDouble() ?? 0.0,
      gamePlayed: data['gameType'] as String? ?? 'Unknown',
    );
  }
}

// ─── THE UNIFIED STATE MANAGER ───
class UserDataProvider extends ChangeNotifier {
  Map<String, dynamic>? _userData;
  bool _isLoading = false;

  Map<String, dynamic>? get userData => _userData;
  bool get isLoading => _isLoading;

  // ─── CARDIO CARE & HYBRID GETTERS ───
  int get xp => _userData?['totalXP'] ?? 0; 
  String get firstName => _userData?['basicInfo']?['firstName'] ?? 'Explorer';

  String get uid => _userData?['uid'] ?? '';
  String get phone => _userData?['phone'] ?? '1111111111';
  int get distanceTraveled => _userData?['totalDistance'] ?? 0;
  int get totalSessions => _userData?['totalSessions'] ?? 0; 
  int get totalRadiusGyration => _userData?['totalRadiusGyration'] ?? 0;
  List<dynamic> get dataPoints => _userData?['dataPoints'] ?? [];

  // Fetch data for the currently logged-in user
  Future<void> fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    debugPrint('🔍 Fetching data for user: ${user.email} (${user.uid})');

    _isLoading = true;
    notifyListeners();

    try {
      // ─── FETCHING FROM THE NEW 'users' ROOT COLLECTION ───
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid) 
          .get();

      if (doc.exists) {
        _userData = doc.data() as Map<String, dynamic>;
        debugPrint('✅ Data loaded successfully for UID: ${user.uid}');
      } else {
        debugPrint('⚠️ No document found, creating one...');
        await createUserDocument(user);
        await fetchUserData(); // Try again after creation
      }
    } catch (e) {
      debugPrint('❌ Error fetching user data: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Helper method to create user document (Updated for Netgauge Hybrid Architecture)
  Future<void> createUserDocument(User user) async {
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch(); // Use a batch write to ensure both documents create simultaneously

    // 1. The Root User Profile
    DocumentReference userRef = firestore.collection('users').doc(user.uid);
    batch.set(userRef, {
      'uid': user.uid,
      'email': user.email ?? 'guest_${user.uid.substring(0, 5)}@demo.com',
      'createdAt': FieldValue.serverTimestamp(),
      'totalSessions': 0,
      'totalSteps': 0,
      'totalDistance': 0,
      'totalXP': 0,
      'basicInfo': {'firstName': 'Explorer'}, // Keep for easy UI rendering
    }, SetOptions(merge: true));

    // 2. The Global Leaderboard Entry
    DocumentReference leaderboardRef = firestore.collection('leaderboard').doc(user.uid);
    batch.set(leaderboardRef, {
      'userId': user.uid,
      'score': 0,
      'totalDistance': 0,
      'rank': 0, 
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Commit the batch
    await batch.commit();
    debugPrint('✅ Netgauge Hybrid Profile & Leaderboard created for UID: ${user.uid}');
  }

  // Used when the user logs out
  void clearData() {
    _userData = null;
    notifyListeners();
    debugPrint('🗑️ User data cleared');
  }
}