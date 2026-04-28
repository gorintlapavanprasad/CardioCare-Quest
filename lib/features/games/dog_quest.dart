import 'dart:async';
import 'dart:convert';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/services/activity_logs.dart';
import 'package:cardio_care_quest/core/services/location_service.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

final loggingService = GetIt.instance<LoggingService>();

class DogQuestGame extends StatefulWidget {
  final double targetDistance;

  const DogQuestGame({super.key, required this.targetDistance});

  @override
  State<DogQuestGame> createState() => _DogQuestGameState();
}

class _DogQuestGameState extends State<DogQuestGame> {
  static const String _gameId = 'dog_quest';
  static const Color _appBarPurple = Color(0xFF4A1D6C);

  late final WebViewController _controller;
  bool _isPlaying = false;
  double _distanceWalked = 0.0;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStream;
  final List<GeoPoint> _pathCoordinates = [];
  late double _targetDistance;
  int _writeCount = 0;
  String? _sessionId;
  String _currentBuddyName = 'Buddy';

  @override
  void initState() {
    super.initState();
    _targetDistance = widget.targetDistance;
    SessionManager.startGame('Dog Walking');
    final userData = Provider.of<UserDataProvider>(context, listen: false);
    loggingService.logEvent('dog_quest_opened', phone: userData.phone);
    _initWebView();
  }

  void _initWebView() {
    debugPrint('🎮 DogQuest: Initializing WebView');
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            debugPrint('🎮 DogQuest: WebView page finished loading: $url');
            _loadGameState();
          },
          onWebResourceError: (error) {
            debugPrint('❌ DogQuest WebView Error: ${error.description}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (JavaScriptMessage message) async {
          try {
            debugPrint(
              '🎮 DogQuest: JS Bridge message received: ${message.message}',
            );
            final data = jsonDecode(message.message);
            switch (data['type']) {
              case 'SET_DOG_NAME':
                debugPrint(
                  '🎮 DogQuest: Setting buddy name to ${data['name']}',
                );
                _updateBuddyName(data['name']);
                break;
              case 'GO_HOME':
                debugPrint('🎮 DogQuest: User requested to go home');
                Navigator.of(context).pop();
                break;
              case 'SAVE_STATE':
                debugPrint('🎮 DogQuest: Saving game state');
                _saveGameState(data['state']);
                break;
              case 'FINISH_QUEST_DATA':
                debugPrint('🎮 DogQuest: Quest finished, ending game');
                _endGame();
                break;
              case 'START_TRACKING':
                debugPrint(
                  '🎮 DogQuest: Starting location tracking for distance ${data['distance']}',
                );
                double incomingTarget = (data['distance'] ?? 500).toDouble();
                bool shouldResume =
                    (incomingTarget == _targetDistance && _distanceWalked > 0);
                if (!shouldResume) {
                  _targetDistance = incomingTarget;
                }
                if (await _ensureLocationPermissionForGame()) {
                  _startGame(resume: shouldResume);
                }
                break;
            }
          } catch (e) {
            debugPrint('❌ DogQuest JS Bridge Error: $e');
          }
        },
      )
      ..loadFlutterAsset('assets/game/dog_quest.html');
  }

  Future<int> _fetchWeeklyQuestCount(String uid) async {
    try {
      final now = DateTime.now();
      // Monday 00:00 of the current ISO week
      final startOfWeek = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday));

      // Single-field equality query — uses Firestore's auto single-field index,
      // so no composite index deploy is required. We filter game/endedAt
      // client-side; for early users with a small session history this is
      // negligible. (For scaled production usage, switch back to the indexed
      // composite query in firestore.indexes.json.)
      final snap = await FirebaseFirestore.instance
          .collection(FirestorePaths.movementData)
          .where('userId', isEqualTo: uid)
          .get();

      int count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['game'] != _gameId) continue;
        final endedAt = data['endedAt'];
        if (endedAt is! Timestamp) continue;
        if (endedAt.toDate().isBefore(startOfWeek)) continue;
        count++;
      }
      return count;
    } catch (e) {
      debugPrint('❌ DogQuest: Weekly quest count error: $e');
      return 0;
    }
  }

  void _pushWeeklyQuestCount(int count) {
    _controller.runJavaScript(
      "if(typeof setWeeklyQuestCount === 'function') { setWeeklyQuestCount($count); }",
    );
  }

  Future<DocumentSnapshot> _fetchStateDocument(String id) async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) {
      debugPrint(
        '⚠️ DogQuest: User not authenticated when fetching state document $id',
      );
      throw StateError('User is not authenticated');
    }
    debugPrint('🎮 DogQuest: Fetching state document $id for user $uid');
    return FirebaseFirestore.instance
        .collection(FirestorePaths.userData)
        .doc(uid)
        .collection(FirestorePaths.gameStates)
        .doc(id)
        .get();
  }

  Future<void> _loadGameState() async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;

    debugPrint(
      '🎮 DogQuest: _loadGameState() called - Auth User: ${uid.isEmpty ? "NOT_AUTHENTICATED" : uid}',
    );

    if (uid.isEmpty) {
      debugPrint('⚠️ DogQuest: No authenticated user, showing scene1 fallback');
      // Fallback: show scene1 even if not authenticated
      _controller.runJavaScript("showPage('scene1');");
      return;
    }

    try {
      bool hasOngoingWalk = false;

      // Fetch and push this week's completed quest count for scene3 stats line.
      _fetchWeeklyQuestCount(uid).then(_pushWeeklyQuestCount);

      debugPrint('🎮 DogQuest: Loading user data for $uid');
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection(FirestorePaths.userData)
          .doc(uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        final savedBuddyName = data['buddyName'] ?? data['dogName'];
        if (savedBuddyName is String && savedBuddyName.isNotEmpty) {
          _currentBuddyName = savedBuddyName;
          debugPrint('🎮 DogQuest: Buddy name loaded: $_currentBuddyName');
          _controller.runJavaScript(
            "if(typeof setBuddyName === 'function') { setBuddyName(${jsonEncode(_currentBuddyName)}); }",
          );
        }
      }

      debugPrint('🎮 DogQuest: Fetching game state for $_gameId');
      DocumentSnapshot gameDoc = await _fetchStateDocument(_gameId);
      if (!gameDoc.exists) {
        debugPrint(
          '🎮 DogQuest: Game state not found for $_gameId, trying walk_buddy',
        );
        gameDoc = await _fetchStateDocument('walk_buddy');
      }

      if (gameDoc.exists && gameDoc.data() != null) {
        final gData = gameDoc.data() as Map<String, dynamic>;
        debugPrint('🎮 DogQuest: Game state found: $gData');

        if (gData.containsKey('gameState')) {
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
          debugPrint(
            '🎮 DogQuest: Resuming ongoing walk - Distance: $_distanceWalked, Target: $_targetDistance',
          );
          _controller.runJavaScript(
            "if(typeof resumeWalk === 'function') { resumeWalk($_distanceWalked, $_targetDistance); }",
          );
          _startGame(resume: true);
        }
      } else {
        debugPrint('🎮 DogQuest: No game state found, starting fresh');
      }

      if (!hasOngoingWalk) {
        debugPrint('🎮 DogQuest: Showing scene1 (quest selection)');
        _controller.runJavaScript("showPage('scene1');");
      }
    } catch (e) {
      debugPrint('❌ DogQuest Load Error: $e');
      // Fallback: show scene1 even on error
      _controller.runJavaScript("showPage('scene1');");
    }
  }

  Future<bool> _ensureLocationPermissionForGame() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await _showLocationServiceDisabledDialog();
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      while (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          final retry = await _showRetryPermissionDialog();
          if (!retry) return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        await _showLocationSettingsDialog();
        return false;
      }

      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      debugPrint('Permission error: $e');
      return false;
    }
  }

  Future<bool> _showRetryPermissionDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Required'),
        content: const Text(
          'Dog Walking needs location permission to complete the walk. Would you like to try again?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _showLocationServiceDisabledDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Services Disabled'),
        content: const Text(
          'Location services are disabled. Please enable them in your device settings so the game can track your movement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLocationSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permanently Denied'),
        content: const Text(
          'Location permission is permanently denied. Open the app settings and enable location access to continue the game.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
          .doc(_gameId)
          .set({'gameState': stateJson}, SetOptions(merge: true));
    }
  }

  Future<void> _startGame({bool resume = false}) async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) {
      debugPrint('❌ DogQuest: Cannot start game - no authenticated user');
      return;
    }
    debugPrint(
      '🎮 DogQuest: Starting game (resume=$resume) for user $uid',
    );

    try {
      final userData = Provider.of<UserDataProvider>(context, listen: false);
      loggingService.logEvent(
        'dog_quest_quest_started',
        parameters: {'target_distance': _targetDistance, 'resumed': resume},
        phone: userData.phone,
      );

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Location permission denied');
        return;
      }

      if (!resume || _sessionId == null) {
        _sessionId = 'dog_${DateTime.now().millisecondsSinceEpoch}';
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
              'game': _gameId,
            }, SetOptions(merge: true));

            final locationRef = firestore
                .collection(FirestorePaths.movementData)
                .doc(_sessionId)
                .collection(FirestorePaths.locationData)
                .doc();
            batch.set(locationRef, {
              'datetime': FieldValue.serverTimestamp(),
              'game': _gameId,
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
              'game': _gameId,
              'geohash': geohash,
              'timestamp': FieldValue.serverTimestamp(),
            });

            final stateRef = firestore
                .collection(FirestorePaths.userData)
                .doc(uid)
                .collection(FirestorePaths.gameStates)
                .doc(_gameId);
            batch.set(stateRef, {
              'ongoingDistance': _distanceWalked,
              'ongoingTarget': _targetDistance,
              'ongoingSessionId': _sessionId,
              'ongoingPath': _pathCoordinates,
            }, SetOptions(merge: true));

            await batch.commit();
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
      debugPrint('GPS Error: $e');
    }
  }

  Future<void> _endGame() async {
    _positionStream?.cancel();
    int pointsGained = _targetDistance <= 500.0
        ? 30
        : (_targetDistance <= 1000.0 ? 60 : 100);

    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) {
      debugPrint('❌ DogQuest: Cannot end game - no authenticated user');
      return;
    }
    debugPrint('🎮 DogQuest: Ending game - Points gained: $pointsGained');

    final userData = Provider.of<UserDataProvider>(context, listen: false);
    loggingService.logEvent(
      'dog_quest_quest_completed',
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
      final batch = firestore.batch();

      final userRef = firestore
          .collection(FirestorePaths.userData)
          .doc(uid);
      final sessionRef = firestore
          .collection(FirestorePaths.movementData)
          .doc(_sessionId);
      final checkRef = sessionRef.collection(FirestorePaths.checkData).doc();
      final stateRef = userRef
          .collection(FirestorePaths.gameStates)
          .doc(_gameId);

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
        'game': _gameId,
        'gameType': _gameId,
        'targetQuest': '${_targetDistance.toInt()}m',
        'totalDistance': _distanceWalked,
        'dogName': _currentBuddyName,
        'buddyName': _currentBuddyName,
        'endedAt': FieldValue.serverTimestamp(),
        'pointsEarned': pointsGained,
      }, SetOptions(merge: true));

      batch.set(checkRef, {
        'event': 'dog_quest_completed',
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

      await batch.commit();

      setState(() {
        _distanceWalked = 0.0;
        _sessionId = null;
        _pathCoordinates.clear();
        _writeCount = 0;
      });

      if (mounted) {
        debugPrint('🎮 DogQuest: Refreshing user data');
        await Provider.of<UserDataProvider>(
          context,
          listen: false,
        ).fetchUserData();
        debugPrint(
          '🎮 DogQuest: Calling onQuestFinished with pointsGained=$pointsGained',
        );
        _controller.runJavaScript('onQuestFinished($pointsGained)');

        // Refresh the weekly quest count so scene3 reflects the new total
        // when the user taps "Do Another Quest".
        final weeklyCount = await _fetchWeeklyQuestCount(uid);
        if (mounted) _pushWeeklyQuestCount(weeklyCount);
      }
    } catch (e) {
      debugPrint('❌ DogQuest Sync Error: $e');
    }
  }

  Future<bool> _confirmExit() async {
    if (!_isPlaying || _distanceWalked <= 0 || _sessionId == null) {
      return true;
    }

    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Dog Walking?'),
        content: const Text(
          'You have an active walk in progress. Do you want to save and exit?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );

    if (shouldLeave == true) {
      if (uid.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection(FirestorePaths.userData)
            .doc(uid)
            .collection(FirestorePaths.gameStates)
            .doc(_gameId)
            .set({
              'ongoingDistance': _distanceWalked,
              'ongoingTarget': _targetDistance,
              'ongoingSessionId': _sessionId,
              'ongoingPath': _pathCoordinates,
            }, SetOptions(merge: true));
      }
    }

    return shouldLeave == true;
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    SessionManager.endGame();
    try {
      final userData = Provider.of<UserDataProvider>(context, listen: false);
      loggingService.logEvent('dog_quest_closed', phone: userData.phone);
    } catch (e) {
      debugPrint('Error logging dispose: $e');
    }
    super.dispose();
  }

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
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _confirmExit();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: _appBarPurple,
          elevation: 0,
          centerTitle: false,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'Dog Walking',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () async {
              final shouldClose = await _confirmExit();
              if (shouldClose && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
