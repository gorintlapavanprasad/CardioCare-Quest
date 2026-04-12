import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/theme/app_colors.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/dashboard/widgets/celebration_modal.dart'; 

class LocationGame extends StatefulWidget {
  final double targetDistance;
  const LocationGame({super.key, required this.targetDistance});

  @override
  State<LocationGame> createState() => _LocationGameState();
}

class _LocationGameState extends State<LocationGame> {
  bool _isPlaying = false;
  bool _isGameOver = false;
  bool _isLoading = false;
  
  double _distanceWalked = 0.0;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStream;
  
  final List<GeoPoint> _pathCoordinates = []; 
  late double _targetDistance; 

  // ─── NETGAUGE ENGINE VARIABLES ───
  int _writeCount = 0; 
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _targetDistance = widget.targetDistance;
  }

  /// Calculates XP based on the chosen quest distance
  int _calculateXPReward() {
    if (_targetDistance <= 50.0) return 30;
    if (_targetDistance <= 500.0) return 60;
    return 100;
  }

  Future<void> _startGame() async {
    setState(() => _isLoading = true);

    try {
      // 1. Check Permissions
      bool serviceEnabled;
      LocationPermission permission;

      if (!kIsWeb) {
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          _showError("Location services are disabled on this device.");
          setState(() => _isLoading = false);
          return;
        }
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError("Location permissions were denied.");
          setState(() => _isLoading = false);
          return;
        }
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      String participantId = authProvider.formData['participant_id'] ?? "Visitor";
      
      _sessionId = "${participantId}_${DateTime.now().millisecondsSinceEpoch}";

      setState(() {
        _isPlaying = true;
        _isLoading = false;
        _distanceWalked = 0.0;
        _isGameOver = false;
        _writeCount = 0;
        _pathCoordinates.clear(); 
        _lastPosition = null;
      });

      // 2. THE NETGAUGE REPLICA ENGINE CONFIGURATION
      _positionStream = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation, // High-fidelity GPS tracking
          distanceFilter: 1, // Require at least 1 meter of movement to filter out standing jitter
        ),
      ).listen(
        (Position position) async {
          // ─── ANTI-GHOSTING FILTER 1: Strict Accuracy ───
          if (position.accuracy > 40.0) {
            debugPrint("Ignored: Poor accuracy (${position.accuracy}m)");
            return; 
          }

          if (_lastPosition != null) {
            double distance = Geolocator.distanceBetween(
              _lastPosition!.latitude, _lastPosition!.longitude,
              position.latitude, position.longitude,
            );
            
            // ─── ANTI-GHOSTING FILTER 2: Speed & Teleportation ───
            final timeDelta = position.timestamp.difference(_lastPosition!.timestamp).inSeconds;
            
            if (timeDelta > 0) {
              double speedMetersPerSecond = distance / timeDelta;
              if (speedMetersPerSecond > 4.0) { // Approx 9 mph (Faster than walking/jogging)
                debugPrint("Ignored: Impossible human speed ($speedMetersPerSecond m/s)");
                return; 
              }
            } else if (distance > 2.0) {
              return; // Ignore instant teleports larger than 2 meters
            }

            // ─── NETGAUGE HEARTBEAT LOGGING (Every 5 valid updates) ───
            _writeCount++;
            if (_writeCount % 5 == 0 && _sessionId != null) {
              await FirebaseFirestore.instance
                  .collection('Movement Data')
                  .doc(_sessionId)
                  .collection('LocationData')
                  .add({
                    'datetime': DateTime.now().toIso8601String(),
                    'game': 'Dog Walking Quest',
                    'geopoint': GeoPoint(position.latitude, position.longitude),
                    'participantId': participantId,
                  });
            }

            setState(() {
              _distanceWalked += distance;
              _pathCoordinates.add(GeoPoint(position.latitude, position.longitude));
            });

            // Trigger completion
            if (_distanceWalked >= _targetDistance) {
              _endGame();
            }

          } else {
            // Log first valid position
            _pathCoordinates.add(GeoPoint(position.latitude, position.longitude));
          }
          _lastPosition = position;
        },
      );
    } catch (e) {
      _showError("GPS Error: ${e.toString()}");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _endGame() async {
    _positionStream?.cancel();
    int xpGained = _calculateXPReward();

    setState(() {
      _isPlaying = false;
      _isGameOver = true;
      _distanceWalked = _targetDistance; 
    });

    if (mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      String participantId = authProvider.formData['participant_id'] ?? "Visitor";

      try {
        final firestore = FirebaseFirestore.instance;
        final userRef = firestore.collection('users').doc(participantId);
        final gameDocRef = userRef.collection('games').doc('Cardio_Explorer');

        // Populate the Cardio Explorer Ghost Document
        await gameDocRef.set({
          'gameName': 'Dog Walking Quest',
          'description': 'Location-based telemetry movement tracking',
          'lastPlayedAt': FieldValue.serverTimestamp(),
          'totalSessions': FieldValue.increment(1),
          'status': 'active',
        }, SetOptions(merge: true));

        // Sync XP to Root Profile
        await userRef.set({
          'xp': FieldValue.increment(xpGained),
          'gamesPlayed': FieldValue.increment(1),
          'lastPlayedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Save the Session Breadcrumb
        String sessionId = DateTime.now().toIso8601String().split('.')[0].replaceAll('T', '_').replaceAll(':', '-');
        await gameDocRef.collection('sessions').doc(sessionId).set({
          'questType': '${_targetDistance.toInt()}m_Walk',
          'distanceWalked': _distanceWalked,
          'playedAt': FieldValue.serverTimestamp(),
          'pathCoordinates': _pathCoordinates, 
          'xpEarned': xpGained,
        });

        // Show the UI Reward
        if (mounted) {
          showCelebrationModal(context, message: "Quest Complete!", xpGained: xpGained);
        }

      } catch (e) {
        debugPrint("💥 Firestore Save Error: $e");
      }
    }
  }

  void _simulateMovement() {
    setState(() {
      _distanceWalked += 5.0;
      if (_lastPosition != null) {
         _pathCoordinates.add(GeoPoint(
           _lastPosition!.latitude + (_distanceWalked * 0.00001), 
           _lastPosition!.longitude + (_distanceWalked * 0.00001)
         ));
      }
      if (_distanceWalked >= _targetDistance) {
        _endGame();
      }
    });
  }

  void _resetGame() {
    setState(() {
      _isGameOver = false;
      _distanceWalked = 0.0;
      _pathCoordinates.clear();
      _writeCount = 0;
    });
  }

  void _showError(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    double progress = (_distanceWalked / _targetDistance).clamp(0.0, 1.0);
    Color activeColor = Color.lerp(AppColors.viridis2, Colors.green.shade500, progress) ?? AppColors.viridis2;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.title),
          onPressed: () => Navigator.of(context).pop(), 
        ),
        title: const Text("Dog Walking Quest", style: TextStyle(color: AppColors.title, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Walk ${_targetDistance.toInt()} Meters", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.title)),
                const SizedBox(height: 8),
                const Text("Keep your phone with you as you move.", style: TextStyle(color: AppColors.subtitle)),
                
                const Spacer(), // Safely pushes the circle to the center

                // Progress Circle
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 240, height: 240, 
                      child: CircularProgressIndicator(
                        value: progress, 
                        strokeWidth: 20, 
                        backgroundColor: AppColors.viridis2.withOpacity(0.1), 
                        valueColor: AlwaysStoppedAnimation<Color>(activeColor)
                      )
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_isGameOver ? Icons.emoji_events : Icons.directions_walk, size: 48, color: activeColor),
                      const SizedBox(height: 8),
                      Text("${_distanceWalked.toStringAsFixed(1)}m", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: AppColors.title)),
                    ])
                  ],
                ),

                const Spacer(), // Safely pushes the buttons to the bottom

                // Interaction Area
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ─── THE MISSING GAME OVER BUTTONS ───
                    if (_isGameOver) ...[
                      Text("Quest Complete! Data Saved.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: activeColor)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.viridis0, 
                          foregroundColor: Colors.white, 
                          minimumSize: const Size(double.infinity, 60), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                        ),
                        onPressed: () => Navigator.pop(context), 
                        child: const Text("RETURN HOME", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.2)),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _resetGame, 
                        child: const Text("PLAY AGAIN", style: TextStyle(color: AppColors.subtitle, fontSize: 16, fontWeight: FontWeight.bold))
                      ),
                    ],

                    if (!_isPlaying && !_isGameOver) ...[
                      // Restored Location Warning
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.viridis2.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.viridis2.withOpacity(0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.location_on, color: AppColors.viridis2, size: 24),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Please ensure your device's GPS/Location is turned ON before starting.",
                                style: TextStyle(color: AppColors.viridis2, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Start Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.viridis0,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 64),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        onPressed: _isLoading ? null : _startGame,
                        child: _isLoading 
                            ? const CircularProgressIndicator(color: Colors.white) 
                            : const Text("START MOVEMENT TRACKING", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      ),
                    ],

                    // Demo Helper Button
                    if (_isPlaying)
                      Center(
                        child: TextButton.icon(
                          onPressed: _simulateMovement,
                          icon: const Icon(Icons.speed, color: AppColors.placeholder),
                          label: const Text("Simulate Step (+5m)", style: TextStyle(color: AppColors.placeholder)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}