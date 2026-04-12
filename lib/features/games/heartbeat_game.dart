import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../core/theme/app_colors.dart';
// Note: Adjust this import to wherever your AuthProvider is located
import '../../features/auth/auth_provider.dart'; 

class HeartbeatGame extends StatefulWidget {
  const HeartbeatGame({super.key});

  @override
  State<HeartbeatGame> createState() => _HeartbeatGameState();
}

class _HeartbeatGameState extends State<HeartbeatGame> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  
  bool _isPlaying = false;
  bool _isGameOver = false;
  int _score = 0;
  int _timeLeft = 15; // 15-second quick demo
  Timer? _gameTimer;
  
  String _feedbackText = "Tap the heart on the beat!";
  Color _feedbackColor = AppColors.subtitle;

  @override
  void initState() {
    super.initState();
    // Setup the rhythmic pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600), // Speed of the heartbeat
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutCubic),
    );

    _pulseController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulseController.reverse();
      } else if (status == AnimationStatus.dismissed && _isPlaying) {
        _pulseController.forward();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _gameTimer?.cancel();
    super.dispose();
  }

  void _startGame() {
    setState(() {
      _isPlaying = true;
      _isGameOver = false;
      _score = 0;
      _timeLeft = 15;
      _feedbackText = "Focus...";
      _feedbackColor = AppColors.placeholder;
    });
    
    _pulseController.forward();

    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_timeLeft > 0) {
          _timeLeft--;
        } else {
          _endGame();
        }
      });
    });
  }

  Future<void> _endGame() async {
    _gameTimer?.cancel();
    _pulseController.stop();
    setState(() {
      _isPlaying = false;
      _isGameOver = true;
      _feedbackText = "Time's Up!";
    });

    // ─── SAVE SCORE TO FIREBASE ───
    if (mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      String participantId = authProvider.formData['participant_id'] ?? "Visitor_Unknown";

      try {
        await FirebaseFirestore.instance.collection('users').doc(participantId).set({
          'latestGameScore': _score,
          'gamesPlayed': FieldValue.increment(1),
          'lastPlayedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        debugPrint("Game score saved for $participantId");
      } catch (e) {
        debugPrint("Error saving game: $e");
      }
    }
  }

  void _handleTap() {
    if (!_isPlaying) return;

    // The heart is "expanded" when the animation value is high (close to 1.0)
    // We give them a small window to hit the beat
    double currentPulse = _pulseController.value;

    setState(() {
      if (currentPulse > 0.75) {
        // Perfect Timing!
        _score += 10;
        _feedbackText = "PERFECT!";
        _feedbackColor = AppColors.viridis2; // Teal
      } else if (currentPulse > 0.5) {
        // Okay Timing
        _score += 5;
        _feedbackText = "Good";
        _feedbackColor = AppColors.viridis4; // Yellow
      } else {
        // Missed the beat
        _score -= 2;
        if (_score < 0) _score = 0;
        _feedbackText = "Miss...";
        _feedbackColor = Colors.redAccent;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.title),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text("Heartbeat Sync", style: TextStyle(color: AppColors.title, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ─── SCORE & TIMER HEADER ───
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("SCORE", style: TextStyle(color: AppColors.placeholder, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      Text("$_score", style: const TextStyle(color: AppColors.viridis0, fontSize: 32, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("TIME", style: TextStyle(color: AppColors.placeholder, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      Text("00:${_timeLeft.toString().padLeft(2, '0')}", style: TextStyle(color: _timeLeft <= 5 ? Colors.redAccent : AppColors.viridis0, fontSize: 32, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ],
              ),
            ),
            
            const Spacer(),

            // ─── THE PULSING HEART (INTERACTIVE AREA) ───
            GestureDetector(
              onTap: _handleTap,
              child: AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppColors.viridis4, AppColors.viridis2],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.viridis2.withOpacity(0.5 * _pulseController.value),
                            blurRadius: 40 * _pulseController.value,
                            spreadRadius: 10 * _pulseController.value,
                          )
                        ],
                      ),
                      child: const Icon(Icons.favorite, color: AppColors.viridis0, size: 80),
                    ),
                  );
                },
              ),
            ),
            
            const Spacer(),

            // ─── FEEDBACK TEXT ───
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _feedbackText,
                key: ValueKey<String>(_feedbackText),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _feedbackColor),
              ),
            ),

            const SizedBox(height: 48),

            // ─── PLAY / PLAY AGAIN BUTTON ───
            if (!_isPlaying)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.viridis0,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 64),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: _startGame,
                  child: Text(
                    _isGameOver ? "PLAY AGAIN" : "START SYNC",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                  ),
                ),
              )
            else 
              const SizedBox(height: 96), // Spacer to keep layout from jumping
          ],
        ),
      ),
    );
  }
}