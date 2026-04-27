import 'package:cardio_care_quest/core/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';
import 'dart:async';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';
import 'package:cardio_care_quest/core/services/activity_logs.dart';

final loggingService = GetIt.instance<LoggingService>();

class LocationGame extends StatefulWidget {
  final double targetDistance;
  const LocationGame({super.key, required this.targetDistance});

  @override
  State<LocationGame> createState() => _LocationGameState();
}

class _LocationGameState extends State<LocationGame> {
  late final WebViewController _controller;

  bool _isPlaying = false;
  double _distanceWalked = 0.0;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStream;

  final List<GeoPoint> _pathCoordinates = [];
  late double _targetDistance;
  int _writeCount = 0;
  String? _sessionId;
  String _currentBuddyName = "Buddy";

  String _geohashFor(double latitude, double longitude, {int precision = 9}) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    var latRange = [-90.0, 90.0];
    var lonRange = [-180.0, 180.0];
    var hash = StringBuffer();
    var bit = 0;
    var ch = 0;
    var evenBit = true;

    while (hash.length < precision) {
      if (evenBit) {
        final mid = (lonRange[0] + lonRange[1]) / 2;
        if (longitude >= mid) {
          ch = (ch << 1) + 1;
          lonRange[0] = mid;
        } else {
          ch <<= 1;
          lonRange[1] = mid;
        }
      } else {
        final mid = (latRange[0] + latRange[1]) / 2;
        if (latitude >= mid) {
          ch = (ch << 1) + 1;
          latRange[0] = mid;
        } else {
          ch <<= 1;
          latRange[1] = mid;
        }
      }

      evenBit = !evenBit;
      if (++bit == 5) {
        hash.write(base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return hash.toString();
  }

  @override
  void initState() {
    super.initState();
    _targetDistance = widget.targetDistance;
    // ─── NETGUAGE PATTERN: Start game session ───
    SessionManager.startGame('Walk Buddy');
    final userData = Provider.of<UserDataProvider>(context, listen: false);
    loggingService.logEvent('walk_buddy_opened', phone: userData.phone);
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (url) => _loadGameState()),
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message);

            if (data['type'] == 'SET_DOG_NAME') {
              _updateBuddyName(data['name']);
            } else if (data['type'] == 'GO_HOME') {
              Navigator.of(context).pop();
            } else if (data['type'] == 'SAVE_STATE') {
              _saveGameState(data['state']);
            } else if (data['type'] == 'FINISH_QUEST_DATA') {
              _endGame();
            } else if (data['type'] == 'START_TRACKING') {
              double incomingTarget = (data['distance'] ?? 500).toDouble();
              bool shouldResume =
                  (incomingTarget == _targetDistance && _distanceWalked > 0);

              if (!shouldResume) {
                _targetDistance = incomingTarget;
              }
              _startGame(resume: shouldResume);
            }
          } catch (e) {
            debugPrint("JS Bridge Error: $e");
          }
        },
      )
      ..loadFlutterAsset('assets/game/walk_buddy.html');
  }

  // ─── LOAD STATE (UPDATED FOR 'users' ROOT) ───
  Future<void> _loadGameState() async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) return;

    try {
      bool hasOngoingWalk = false;

      // 0. REQUEST LOCATION PERMISSION EARLY
      // This ensures permissions are ready before any tracking begins
      _requestLocationPermission();

      // 1. Fetch buddy name from the user document.
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection(FirestorePaths.userData)
          .doc(uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        final savedBuddyName = data['buddyName'] ?? data['dogName'];
        if (savedBuddyName is String && savedBuddyName.isNotEmpty) {
          _currentBuddyName = savedBuddyName;
          _controller.runJavaScript(
            "if(typeof setDogName === 'function') { setDogName(${jsonEncode(_currentBuddyName)}); }",
          );
          // isNewUser = false;
        }
      }

      // 2. Fetch UI state
      DocumentSnapshot gameDoc = await FirebaseFirestore.instance
          .collection(FirestorePaths.userData)
          .doc(uid)
          .collection(FirestorePaths.gameStates)
          .doc('walk_buddy')
          .get();

      if (gameDoc.exists && gameDoc.data() != null) {
        final gData = gameDoc.data() as Map<String, dynamic>;

        if (gData.containsKey('gameState')) {
          // isNewUser = false;
          _controller.runJavaScript(
            "if(typeof hydrateState === 'function') { hydrateState(${jsonEncode(gData['gameState'])}); }",
          );
        }

        if (gData.containsKey('ongoingDistance') &&
            gData['ongoingDistance'] > 0) {
          _distanceWalked = (gData['ongoingDistance'] ?? 0.0).toDouble();
          _targetDistance = (gData['ongoingTarget'] ?? 50.0).toDouble();
          _sessionId = gData['ongoingSessionId'];

          if (gData.containsKey('ongoingPath')) {
            List<dynamic> savedPath = gData['ongoingPath'];
            _pathCoordinates.clear();
            _pathCoordinates.addAll(savedPath.map((p) => p as GeoPoint));
          }

          hasOngoingWalk = true;
          _controller.runJavaScript(
            "if(typeof resumeWalk === 'function') { resumeWalk($_distanceWalked, $_targetDistance); }",
          );
          _startGame(resume: true);
        }
      }

      if (hasOngoingWalk) {
        // UI is already handling this
      } else {
        // Let HTML show the narrative flow naturally (page-home by default)
        // Returning users will see the full narrative intro before reaching quests
        _controller.runJavaScript("showPage('page-home');");
      }
    } catch (e) {
      debugPrint("Load Error: $e");
    }
  }

  // Request location permission early so it's ready when tracking starts
  Future<void> _requestLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint("Permission request error: $e");
    }
  }

  Future<void> _updateBuddyName(String newName) async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isNotEmpty) {
      setState(() => _currentBuddyName = newName);
      await FirebaseFirestore.instance
          .collection(FirestorePaths.userData)
          .doc(uid)
          .update({'dogName': newName, 'buddyName': newName});
    }
  }

  Future<void> _saveGameState(String stateJson) async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.userData)
          .doc(uid)
          .collection(FirestorePaths.gameStates)
          .doc('walk_buddy')
          .set({'gameState': stateJson}, SetOptions(merge: true));
    }
  }

  // ─── TRACKING ENGINE (UPDATED TO SPLIT HEATMAP DATA) ───
  Future<void> _startGame({bool resume = false}) async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) return;

    try {
      // Log quest start event (netguage pattern)
      final userData = Provider.of<UserDataProvider>(context, listen: false);
      loggingService.logEvent(
        'walk_buddy_quest_started',
        parameters: {'target_distance': _targetDistance, 'resumed': resume},
        phone: userData.phone,
      );

      // Location permission was already requested early in _loadGameState()
      // Just check if we have permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint("Location permission denied");
        return;
      }

      if (!resume || _sessionId == null) {
        _sessionId = "walk_${DateTime.now().millisecondsSinceEpoch}";
        _distanceWalked = 0.0;
        _writeCount = 0;
        _pathCoordinates.clear();
      }

      setState(() {
        _isPlaying = true;
        _lastPosition = null;
      });

      if (resume) {
        _controller.runJavaScript(
          "if(typeof updateGameProgress === 'function') { updateGameProgress($_distanceWalked); }",
        );
      }

      _positionStream = LocationDispatcher.stream.listen((
        Position position,
      ) async {
        if (position.accuracy > 35.0) return;

        if (_lastPosition != null) {
          double distance = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );

          _writeCount++;

          if (_writeCount % 5 == 0 && _sessionId != null) {
            final firestore = FirebaseFirestore.instance;
            final batch = firestore.batch();
            final point = GeoPoint(position.latitude, position.longitude);
            final geohash = _geohashFor(position.latitude, position.longitude);

            final sessionRef = firestore
                .collection(FirestorePaths.movementData)
                .doc(_sessionId);
            batch.set(sessionRef, {
              'sessionId': _sessionId,
              'created': FieldValue.serverTimestamp(),
              'test': false,
              'userId': uid,
              'game': 'walk_buddy',
            }, SetOptions(merge: true));

            final locationRef = firestore
                .collection(FirestorePaths.movementData)
                .doc(_sessionId)
                .collection(FirestorePaths.locationData)
                .doc();
            batch.set(locationRef, {
              'datetime': FieldValue.serverTimestamp(),
              'game': 'walk_buddy',
              'geopoint': point,
              'geohash': geohash,
              'latitude': position.latitude,
              'longitude': position.longitude,
              'test': false,
            });

            final geoRef = firestore
                .collection(FirestorePaths.dataPoints)
                .doc();
            batch.set(geoRef, {
              'location': {'geopoint': point},
              'userId': uid,
              'sessionId': _sessionId,
              'game': 'walk_buddy',
              'geohash': geohash,
              'timestamp': FieldValue.serverTimestamp(),
            });

            final stateRef = firestore
                .collection(FirestorePaths.userData)
                .doc(uid)
                .collection(FirestorePaths.gameStates)
                .doc('walk_buddy');
            batch.set(stateRef, {
              'ongoingDistance': _distanceWalked,
              'ongoingTarget': _targetDistance,
              'ongoingSessionId': _sessionId,
              'ongoingPath': _pathCoordinates,
            }, SetOptions(merge: true));

            await batch.commit(); // Push all data points at once safely
          }

          setState(() {
            _distanceWalked += distance;
            _pathCoordinates.add(
              GeoPoint(position.latitude, position.longitude),
            );
          });

          _controller.runJavaScript(
            "if(typeof updateGameProgress === 'function') { updateGameProgress($_distanceWalked, $_targetDistance); }",
          );

          if (_distanceWalked >= _targetDistance && _isPlaying) {
            _endGame();
          }
        }
        _lastPosition = position;
      });
    } catch (e) {
      debugPrint("GPS Error: $e");
    }
  }

  // ─── THE FINAL SYNC (THE FULL HYBRID PAYLOAD) ───
  Future<void> _endGame() async {
    _positionStream?.cancel();
    int pointsGained = _targetDistance <= 500.0
        ? 30
        : (_targetDistance <= 1000.0 ? 60 : 100);

    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) return;

    // Log quest completion (netguage pattern)
    final userData = Provider.of<UserDataProvider>(context, listen: false);
    loggingService.logEvent(
      'walk_buddy_quest_completed',
      parameters: {
        'distance_walked': _distanceWalked.toInt(),
        'target_distance': _targetDistance.toInt(),
        'points_earned': pointsGained,
        'buddy_name': _currentBuddyName,
      },
      phone: userData.phone,
    );

    setState(() => _isPlaying = false);

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch(); // Batch for ultimate safety

      final userRef = firestore
          .collection(FirestorePaths.userData)
          .doc(uid);
      final sessionRef = firestore
          .collection(FirestorePaths.movementData)
          .doc(_sessionId);
      final checkRef = sessionRef.collection(FirestorePaths.checkData).doc();
      final stateRef = userRef
          .collection(FirestorePaths.gameStates)
          .doc('walk_buddy');

      // 1. Root Profile Sync (Using Netgauge Naming conventions)
      batch.update(userRef, {
        'points': FieldValue.increment(pointsGained),
        'totalDistance': FieldValue.increment(_distanceWalked.toInt()),
        'totalSessions': FieldValue.increment(1),
        'distanceTraveled': FieldValue.increment(_distanceWalked.toInt()),
        'measurementsTaken': FieldValue.increment(1),
        'lastPlayedAt': FieldValue.serverTimestamp(),
      });

      batch.set(sessionRef, {
        'sessionId': _sessionId,
        'created': FieldValue.serverTimestamp(),
        'test': false,
        'game': 'walk_buddy',
        'gameType': 'walk_buddy',
        'targetQuest': '${_targetDistance.toInt()}m',
        'totalDistance': _distanceWalked,
        'dogName': _currentBuddyName,
        'buddyName': _currentBuddyName,
        'endedAt': FieldValue.serverTimestamp(),
        'pointsEarned': pointsGained,
      }, SetOptions(merge: true));

      batch.set(checkRef, {
        'event': 'walk_buddy_completed',
        'latitude': _pathCoordinates.isNotEmpty
            ? _pathCoordinates.last.latitude
            : null,
        'longitude': _pathCoordinates.isNotEmpty
            ? _pathCoordinates.last.longitude
            : null,
        'sessionID': _sessionId,
        'sessionId': _sessionId,
        'downloadSpeed': 0,
        'uploadSpeed': 0,
        'latency': 0,
        'timestamp': FieldValue.serverTimestamp(),
      });

      batch.set(stateRef, {
        'ongoingDistance': FieldValue.delete(),
        'ongoingTarget': FieldValue.delete(),
        'ongoingSessionId': FieldValue.delete(),
        'ongoingPath': FieldValue.delete(),
      }, SetOptions(merge: true));

      // Execute the batch!
      await batch.commit();

      setState(() {
        _distanceWalked = 0.0;
        _sessionId = null;
        _pathCoordinates.clear();
        _writeCount = 0;
      });

      if (mounted) {
        await Provider.of<UserDataProvider>(
          context,
          listen: false,
        ).fetchUserData();
        _controller.runJavaScript("onQuestFinished($pointsGained)");
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    // ─── NETGUAGE PATTERN: End game session ───
    SessionManager.endGame();
    try {
      final userData = Provider.of<UserDataProvider>(context, listen: false);
      loggingService.logEvent('walk_buddy_closed', phone: userData.phone);
    } catch (e) {
      debugPrint('Error logging dispose: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () async {
            if (_isPlaying && _distanceWalked > 0 && _sessionId != null) {
              final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
              if (uid.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection(FirestorePaths.userData)
                    .doc(uid)
                    .collection(FirestorePaths.gameStates)
                    .doc('walk_buddy')
                    .set({
                      'ongoingDistance': _distanceWalked,
                      'ongoingTarget': _targetDistance,
                      'ongoingSessionId': _sessionId,
                      'ongoingPath': _pathCoordinates,
                    }, SetOptions(merge: true));
              }
            }
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        bottom: false,
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
