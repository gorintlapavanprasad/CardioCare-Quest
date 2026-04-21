import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cardio_care_quest/user_data_manager.dart';

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
  String _currentDogName = "Buddy";

  @override
  void initState() {
    super.initState();
    _targetDistance = widget.targetDistance;
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) => _loadGameState(),
      ))
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message);
            
            if (data['type'] == 'SET_DOG_NAME') {
              _updateDogName(data['name']);
            } else if (data['type'] == 'GO_HOME') {
              Navigator.of(context).pop();
            } else if (data['type'] == 'SAVE_STATE') {
              _saveGameState(data['state']);
            } else if (data['type'] == 'FINISH_QUEST_DATA') {
              _endGame();
            }
            else if (data['type'] == 'START_TRACKING') {
              double incomingTarget = (data['distance'] ?? 500).toDouble();
              bool shouldResume = (incomingTarget == _targetDistance && _distanceWalked > 0);
              
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
      ..loadFlutterAsset('assets/game/dog_quest.html');
  }

  // ─── LOAD STATE (UPDATED FOR 'users' ROOT) ───
  Future<void> _loadGameState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      bool isNewUser = true;
      bool hasOngoingWalk = false;

      // 1. Fetch Dog Name from the new 'users' collection
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        if (data.containsKey('dogName')) {
          _currentDogName = data['dogName'];
          _controller.runJavaScript("if(typeof setDogName === 'function') { setDogName('$_currentDogName'); }");
          isNewUser = false; 
        }
      }

      // 2. Fetch UI state
      DocumentSnapshot gameDoc = await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('gameStates').doc('dog_walking').get();

      if (gameDoc.exists && gameDoc.data() != null) {
        final gData = gameDoc.data() as Map<String, dynamic>;
        
        if (gData.containsKey('gameState')) {
          _controller.runJavaScript("if(typeof hydrateState === 'function') { hydrateState('${gData['gameState']}'); }");
        }
        
        if (gData.containsKey('ongoingDistance') && gData['ongoingDistance'] > 0) {
          _distanceWalked = (gData['ongoingDistance'] ?? 0.0).toDouble();
          _targetDistance = (gData['ongoingTarget'] ?? 50.0).toDouble(); 
          _sessionId = gData['ongoingSessionId'];
          
          if (gData.containsKey('ongoingPath')) {
            List<dynamic> savedPath = gData['ongoingPath'];
            _pathCoordinates.clear();
            _pathCoordinates.addAll(savedPath.map((p) => p as GeoPoint));
          }

          hasOngoingWalk = true;
          _controller.runJavaScript("if(typeof resumeWalk === 'function') { resumeWalk($_distanceWalked, $_targetDistance); }");
          _startGame(resume: true);
        }
      }

      if (hasOngoingWalk) {
        // UI is already handling this
      } else if (!isNewUser) {
        _controller.runJavaScript("showPage('page-quests');");
      } else {
        _controller.runJavaScript("showPage('page-home');");
      }
    } catch (e) {
      debugPrint("Load Error: $e");
    }
  }

  Future<void> _updateDogName(String newName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _currentDogName = newName);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'dogName': newName});
    }
  }

  Future<void> _saveGameState(String stateJson) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid)
          .collection('gameStates').doc('dog_walking').set({'gameState': stateJson}, SetOptions(merge: true));
    }
  }

  // ─── TRACKING ENGINE (UPDATED TO SPLIT HEATMAP DATA) ───
  Future<void> _startGame({bool resume = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
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
        _controller.runJavaScript("if(typeof updateGameProgress === 'function') { updateGameProgress($_distanceWalked); }");
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 2),
      ).listen((Position position) async {
        if (position.accuracy > 35.0) return; 

        if (_lastPosition != null) {
          double distance = Geolocator.distanceBetween(
            _lastPosition!.latitude, _lastPosition!.longitude,
            position.latitude, position.longitude,
          );
          
          _writeCount++;
          
          if (_writeCount % 5 == 0 && _sessionId != null) {
            final firestore = FirebaseFirestore.instance;
            final batch = firestore.batch();
            final point = GeoPoint(position.latitude, position.longitude);

            // 1. Save Breadcrumbs to the User's Session (The Netgauge standard)
            final locationRef = firestore
                .collection('users').doc(user.uid)
                .collection('sessions').doc(_sessionId)
                .collection('locations').doc();
            batch.set(locationRef, {
              'geopoint': point,
              'timestamp': FieldValue.serverTimestamp(),
            });

            // 2. Save to Top-Level Global Heatmap (For the Researchers!)
            final geoRef = firestore.collection('geo_points').doc();
            batch.set(geoRef, {
              'geopoint': point,
              'userId': user.uid,
              'gameType': 'dog_walking',
              'timestamp': FieldValue.serverTimestamp(),
            });
            
            // 3. Save Ongoing Progress
            final stateRef = firestore
                .collection('users').doc(user.uid)
                .collection('gameStates').doc('dog_walking');
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
            _pathCoordinates.add(GeoPoint(position.latitude, position.longitude));
          });

          _controller.runJavaScript("if(typeof updateGameProgress === 'function') { updateGameProgress($_distanceWalked); }");

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
    int xpGained = _targetDistance <= 500.0 ? 30 : (_targetDistance <= 1000.0 ? 60 : 100);
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isPlaying = false);

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch(); // Batch for ultimate safety

      final userRef = firestore.collection('users').doc(user.uid);
      final sessionRef = userRef.collection('sessions').doc(_sessionId);
      final stateRef = userRef.collection('gameStates').doc('dog_walking');
      final leaderboardRef = firestore.collection('leaderboard').doc(user.uid);

      // 1. Root Profile Sync (Using Netgauge Naming conventions)
      batch.update(userRef, {
        'totalXP': FieldValue.increment(xpGained),
        'totalDistance': FieldValue.increment(_distanceWalked.toInt()),
        'totalSessions': FieldValue.increment(1),
        'lastPlayedAt': FieldValue.serverTimestamp(),
      });

      // 2. Global Leaderboard Sync
      batch.update(leaderboardRef, {
        'score': FieldValue.increment(xpGained),
        'totalDistance': FieldValue.increment(_distanceWalked.toInt()),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // 3. Final Session History (Under the user)
      batch.set(sessionRef, {
        'sessionId': _sessionId, 
        'gameType': 'dog_walking',
        'targetQuest': '${_targetDistance.toInt()}m',
        'totalDistance': _distanceWalked,
        'dogName': _currentDogName,
        'endedAt': FieldValue.serverTimestamp(),
        'xpEarned': xpGained,
      }, SetOptions(merge: true));

      // 4. Wipe Ongoing Memory
      batch.update(stateRef, {
        'ongoingDistance': FieldValue.delete(),
        'ongoingTarget': FieldValue.delete(),
        'ongoingSessionId': FieldValue.delete(),
        'ongoingPath': FieldValue.delete(), 
      });

      // Execute the batch!
      await batch.commit();

      setState(() {
        _distanceWalked = 0.0;
        _sessionId = null;
        _pathCoordinates.clear();
        _writeCount = 0;
      });

      if (mounted) {
        await Provider.of<UserDataProvider>(context, listen: false).fetchUserData();
        _controller.runJavaScript("onQuestFinished($xpGained)");
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
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
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                // Pointing back to 'users' collection for the partial save
                await FirebaseFirestore.instance
                    .collection('users').doc(user.uid)
                    .collection('gameStates').doc('dog_walking').set({
                      'ongoingDistance': _distanceWalked,
                      'ongoingTarget': _targetDistance,
                      'ongoingSessionId': _sessionId,
                      'ongoingPath': _pathCoordinates,
                    }, SetOptions(merge: true));
              }
            }
            if (mounted) Navigator.of(context).pop(); 
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