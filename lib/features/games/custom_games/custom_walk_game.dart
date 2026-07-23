// CustomWalkGame - a real walk you go on, tracked by GPS. This is the
// walk game a user built themselves. It works just like the built-in
// Dog Quest walk: it follows your location, saves your route as you go,
// gives points when you reach the goal, and takes a health snapshot at
// the end. The only difference is the user picked the goal distance.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../../core/hooks/hooks.dart';
import '../../../core/providers/user_data_manager.dart';
import '../../../core/services/location_service.dart';
import 'custom_game.dart';
import 'custom_games_repository.dart';

// The walk game screen.
class CustomWalkGame extends StatefulWidget {
  final CustomGame game;
  const CustomWalkGame({super.key, required this.game});

  @override
  State<CustomWalkGame> createState() => _CustomWalkGameState();
}

class _CustomWalkGameState extends State<CustomWalkGame> {
  StreamSubscription<Position>? _positionSub; // our GPS listener
  Position? _lastPosition; // where we were last, to measure the step
  double _distanceWalked = 0; // meters so far
  final List<GeoPoint> _path = []; // the route, point by point
  int _pingCount = 0; // how many GPS updates we've gotten
  late final DateTime _startedAt;
  late final String _sessionId; // ties this one walk together
  String get _gameId => 'custom_${widget.game.id}';

  bool _walking = false; // are we currently walking?
  bool _completed = false; // is the walk finished?
  String? _error; // message to show if something went wrong

  // Only save to the cloud every 5th GPS update, to save data.
  static const _pushPingEveryNFixes = 5;

  // Runs once when the screen opens: set up ids and note the game opened.
  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _sessionId = MovementHooks.generateSessionId(_gameId);
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    // ignore: unawaited_futures
    TelemetryHooks.logEvent(
      'custom_game_opened',
      parameters: {
        'gameId': widget.game.id,
        'sessionId': _sessionId,
        'gameType': 'walk',
        'targetDistance': widget.game.targetDistance,
      },
      userId: uid.isEmpty ? null : uid,
    );
  }

  // Stop listening to GPS when the screen closes, so it doesn't keep
  // running in the background.
  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  // Runs when the user taps START. Checks location permission, then
  // begins listening to GPS. Shows an error if location is off/blocked.
  Future<void> _startWalk() async {
    final messenger = ScaffoldMessenger.of(context);

    // Make sure location is turned on and we're allowed to use it.
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _error = 'Turn on Location Services to start the walk.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _error = 'Location permission is needed for walking quests.');
      return;
    }

    setState(() {
      _walking = true;
      _error = null;
      _distanceWalked = 0;
      _path.clear();
      _pingCount = 0;
    });

    // Start following the phone's location. Each new spot calls _onPosition.
    _positionSub = LocationDispatcher.stream.listen(_onPosition,
        onError: (e) {
      messenger.showSnackBar(SnackBar(content: Text('GPS error: $e')));
    });
  }

  // Runs each time the phone reports a new location. Adds up the distance
  // walked, records the route, and saves to the cloud now and then.
  void _onPosition(Position p) {
    if (_completed) return;
    final last = _lastPosition;
    if (last != null) {
      // How far we moved since the last spot, in meters.
      final delta = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        p.latitude,
        p.longitude,
      );
      // Ignore crazy jumps and shaky readings (bad GPS), so a glitch
      // can't fake a bunch of distance. >40m in a second is too fast.
      if (delta < 40 && (p.accuracy < 25)) {
        _distanceWalked += delta;
      }
    }
    _lastPosition = p;
    _path.add(GeoPoint(p.latitude, p.longitude));
    _pingCount++;

    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    // Only save every 5th update, to keep data use down.
    if (_pingCount % _pushPingEveryNFixes == 0 && uid.isNotEmpty) {
      // ignore: unawaited_futures
      MovementHooks.pushPing(
        uid: uid,
        sessionId: _sessionId,
        gameId: _gameId,
        position: p,
        distanceWalked: _distanceWalked,
        targetDistance: widget.game.targetDistance.toDouble(),
        pathCoordinates: List<GeoPoint>.from(_path),
      );
    }

    setState(() {});

    // Finish on its own once the goal distance is reached.
    if (_distanceWalked >= widget.game.targetDistance) {
      _finishWalk(autoCompleted: true);
    }
  }

  // Ends the walk (either the goal was reached, or the user tapped
  // "I'm done"). Works out the points, saves everything, awards points.
  Future<void> _finishWalk({required bool autoCompleted}) async {
    if (_completed) return;
    setState(() => _completed = true);
    await _positionSub?.cancel(); // stop the GPS
    _positionSub = null;

    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    final game = widget.game;
    // Full points if you reached the goal, otherwise a share based on how
    // far you got. Round down so a not-quite walk can't count as full.
    final ratio = (_distanceWalked / game.targetDistance).clamp(0.0, 1.0);
    final pointsEarned = (game.pointsReward * ratio).floor();

    if (uid.isNotEmpty) {
      // Save the finished walk: route, distance, points, lifetime totals.
      // ignore: unawaited_futures
      MovementHooks.endSession(
        uid: uid,
        sessionId: _sessionId,
        gameId: _gameId,
        distanceWalked: _distanceWalked,
        targetDistance: game.targetDistance.toDouble(),
        pointsEarned: pointsEarned,
        buddyName: '',
        pathCoordinates: _path,
        completionEventName: 'custom_walk_completed',
      );
      // Mark this game finished one more time (updates the card).
      // ignore: unawaited_futures
      CustomGamesRepository.instance.markCompleted(
        uid: uid,
        gameId: game.id,
      );
      // Grab a health snapshot from the watch/wearable at the end.
      // ignore: unawaited_futures
      HealthHooks.logSnapshot(
        uid: uid,
        gameId: _gameId,
        sessionId: _sessionId,
      );
    }

    // Show the new points on screen right away (only if any were earned).
    if (mounted && pointsEarned > 0) {
      PointsHooks.applyIncrements(context, {
        'points': pointsEarned,
        'totalSessions': 1,
        'totalDistance': _distanceWalked.toInt(),
      });
    }

    // Note that the walk was finished (for the researchers).
    // ignore: unawaited_futures
    TelemetryHooks.logEvent(
      'custom_game_session_completed',
      parameters: {
        'gameId': game.id,
        'sessionId': _sessionId,
        'gameType': 'walk',
        'targetDistance': game.targetDistance,
        'distanceWalked': _distanceWalked.toInt(),
        'pointsEarned': pointsEarned,
        'autoCompleted': autoCompleted,
        'durationMs':
            DateTime.now().difference(_startedAt).inMilliseconds,
      },
      userId: uid.isEmpty ? null : uid,
    );
  }

  // Shows the right screen for where we are: welcome (before starting),
  // the live walk, or the result once finished.
  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    // How far along we are (0 to 1) and how many meters are left.
    final progress = (_distanceWalked / game.targetDistance).clamp(0.0, 1.0);
    final remaining =
        (game.targetDistance - _distanceWalked).clamp(0, game.targetDistance);

    return Scaffold(
      backgroundColor: const Color(0xFF1a1b2e),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a3a5c), Color(0xFF2a5074), Color(0xFF3a6a94)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(title: game.title),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: _completed
                    ? _ResultView(
                        game: game,
                        distanceWalked: _distanceWalked,
                        onDone: () => Navigator.of(context).pop(),
                      )
                    : _walking
                        ? _ActiveWalkView(
                            game: game,
                            distanceWalked: _distanceWalked,
                            remaining: remaining.toDouble(),
                            progress: progress,
                            onFinishEarly: () =>
                                _finishWalk(autoCompleted: false),
                          )
                        : _WelcomeView(
                            game: game,
                            error: _error,
                            onStart: _startWalk,
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- SCREEN PARTS (looks only) ----

// The top bar with the game's title.
class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    // Push the title down past the phone's status bar (clock/battery)
    // so it isn't hidden behind it.
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topInset + 16, 20, 16),
      color: Colors.black.withValues(alpha: 0.18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Text(
            '≡',
            style: TextStyle(color: Colors.white, fontSize: 24, height: 1),
          ),
        ],
      ),
    );
  }
}

// Before-start screen: the goal ("Walk 500 meters...") and a START button.
class _WelcomeView extends StatelessWidget {
  final CustomGame game;
  final String? error;
  final VoidCallback onStart;
  const _WelcomeView({required this.game, required this.error, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.directions_walk, color: Colors.white, size: 72),
        const SizedBox(height: 16),
        Text(
          game.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Walk ${game.targetDistance} meters to earn ${game.pointsReward} points.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 15,
            height: 1.4,
          ),
        ),
        if (game.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            game.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
        const Spacer(),
        _PrimaryButton(label: 'START WALK', onPressed: onStart),
        const SizedBox(height: 16),
      ],
    );
  }
}

// While walking: shows meters done, a progress bar, and an "I'm done"
// button to stop early.
class _ActiveWalkView extends StatelessWidget {
  final CustomGame game;
  final double distanceWalked;
  final double remaining;
  final double progress;
  final VoidCallback onFinishEarly;

  const _ActiveWalkView({
    required this.game,
    required this.distanceWalked,
    required this.remaining,
    required this.progress,
    required this.onFinishEarly,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          '${distanceWalked.toInt()} m',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 56,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'of ${game.targetDistance} m',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 24),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 12,
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFFfde725)),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          remaining > 0
              ? '${remaining.toInt()} m to go'
              : 'Target reached',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        _SecondaryButton(label: 'I\'M DONE', onPressed: onFinishEarly),
        const SizedBox(height: 16),
      ],
    );
  }
}

// After finishing: "Walk complete", points earned, and a DONE button.
class _ResultView extends StatelessWidget {
  final CustomGame game;
  final double distanceWalked;
  final VoidCallback onDone;
  const _ResultView({
    required this.game,
    required this.distanceWalked,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    // Same points math as when we finished, just to show the number.
    final ratio = (distanceWalked / game.targetDistance).clamp(0.0, 1.0);
    final earned = (game.pointsReward * ratio).floor();
    return Column(
      children: [
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              Text(
                '+$earned',
                style: const TextStyle(
                  color: Color(0xFFfde725),
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Walk complete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'You walked ${distanceWalked.toInt()} meters of '
                '${game.targetDistance}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        _PrimaryButton(label: 'DONE', onPressed: onDone),
        const SizedBox(height: 16),
      ],
    );
  }
}

// The big white button (START WALK / DONE).
class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1a3a5c),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// The outlined button (the "I'm done" stop-early button).
class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _SecondaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          foregroundColor: Colors.white,
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.4),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
