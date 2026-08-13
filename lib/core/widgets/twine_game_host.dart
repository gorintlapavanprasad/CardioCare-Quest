import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/services/location_service.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';
import 'package:cardio_care_quest/core/widgets/game_web_style.dart';
import 'package:cardio_care_quest/features/games/game_completion_signal.dart';

// TwineGameHost - runs a GPS-tracked walking game (Twine HTML) inside a WebView.
// Handles GPS tracking, the JS bridge, saving progress, and finishing the walk.
// One reusable host so all walking games share the same logic.

// Callback for game-specific bridge messages. Return true if handled, false to fall through.
typedef OnTwineBridgeMessage = Future<bool> Function(
  Map<String, dynamic> data,
  TwineGameHostController controller,
);

// Returns points for a finished walk. Default: 30 / 60 / 100 for short/medium/long.
typedef PointsCalculator = int Function(double targetDistance);

// The default scoring rule if a game doesn't supply its own.
int _defaultPointsCalculator(double target) =>
    target <= 500 ? 30 : (target <= 1000 ? 60 : 100);

// Reusable host for any GPS-tracked Twine game. Drop a .html file into assets,
// then wrap this widget with the game's id, title, asset path, and target distance.
// The widget you add to a screen. The actual work happens in the State below.
class TwineGameHost extends StatefulWidget {
  // Unique game id (e.g. 'dog_quest'). Used in Firestore docs and resume state.
  final String gameId;

  // Title shown in the UI (e.g. 'Dog Walking').
  final String gameTitle;

  // Path to the Twine HTML file in assets (must be in pubspec.yaml).
  final String htmlAsset;

  // Walk target in meters. Can be overridden by the game's START_TRACKING message.
  final double targetDistance;

  // App bar color. Defaults to deep purple.
  final Color appBarColor;

  // Optional custom points formula. Default: 30/60/100 for short/medium/long walks.
  final PointsCalculator pointsCalculator;

  // Optional handler for game-specific bridge messages. Return true to claim a message.
  final OnTwineBridgeMessage? onCustomBridgeMessage;

  // Optional custom exit dialog. If null, shows the default "save and exit?" prompt.
  final Future<bool> Function(BuildContext context)? confirmExitDialog;

  const TwineGameHost({
    super.key,
    required this.gameId,
    required this.gameTitle,
    required this.htmlAsset,
    required this.targetDistance,
    this.appBarColor = const Color(0xFF4A1D6C),
    this.pointsCalculator = _defaultPointsCalculator,
    this.onCustomBridgeMessage,
    this.confirmExitDialog,
  });

  @override
  State<TwineGameHost> createState() => _TwineGameHostState();
}

// ---- CONTROLLER ----

// Handed to custom bridge-message handlers so they can call into the WebView,
// end the game, or navigate home without touching the full host state.
class TwineGameHostController {
  final WebViewController webView;
  final Future<void> Function() endGame;
  final Future<void> Function() goHome;

  TwineGameHostController._({
    required this.webView,
    required this.endGame,
    required this.goHome,
  });
}

// Holds all live state for one play: GPS stream, distance, session ids, flags.
class _TwineGameHostState extends State<TwineGameHost> {
  // ---- STATE ----
  late final WebViewController _controller; // drives the WebView (the game page)
  late TwineGameHostController _externalController; // remote control for handlers

  bool _isPlaying = false; // is a walk currently running?
  double _distanceWalked = 0.0; // metres walked so far this walk
  Position? _lastPosition; // last GPS fix, to measure the step to the next one
  StreamSubscription<Position>? _positionStream; // our live GPS feed
  final List<GeoPoint> _pathCoordinates = []; // the trail of points we walked
  late double _targetDistance; // metres you need to walk to finish
  int _writeCount = 0; // counts GPS fixes so we save only every 5th one
  String? _sessionId; // id for this one walk (null when not walking)
  String _currentBuddyName = 'Buddy'; // the pet/companion name shown in-game

  // Timer that re-checks completion if GPS goes quiet (emulator, lost lock, etc.).
  Timer? _completionWatchdog;

  // Prevents the watchdog and the GPS stream from both calling _endGame at once.
  bool _endingGame = false;

  // Per-game record of the last completed session id. Class-level so it survives
  // navigating away and back. Guards against stale 'ongoing*' fields left by a
  // late GPS write landing after the end-game delete.
  static final Map<String, String> _justCompletedSessionByGame = {};

  // Id for this screen open (one "host session"). Tagged on every telemetry event.
  // Different from _sessionId, which is per-walk.
  late final String _hostSessionId;

  // True while the HTML is loading. Shows a spinner so there's no blank screen.
  bool _loading = true;

  // When this screen opened, for calculating play duration.
  late final DateTime _hostStartedAt;

  // Ensures the gameSessions summary is written exactly once per visit.
  bool _sessionSummaryWritten = false;

  // True once HealthKit vitals have been grabbed. Prevents a double snapshot
  // when a player completes a walk and then backs out.
  bool _snapshotLogged = false;

  String get _phone =>
      Provider.of<UserDataProvider>(context, listen: false).phone;
  String get _uid =>
      Provider.of<UserDataProvider>(context, listen: false).uid;

  // Copied before dispose() so Provider.of can't be called after detach.
  String _phoneForDispose = '';
  String _uidForDispose = '';

  // ---- SETUP / LIFECYCLE ----

  @override
  void initState() {
    super.initState();
    _targetDistance = widget.targetDistance;
    _hostStartedAt = DateTime.now();
    _hostSessionId =
        '${widget.gameId}_host_${_hostStartedAt.millisecondsSinceEpoch}';
    SessionManager.startGame(widget.gameTitle);
    TelemetryHooks.logEvent(
      '${widget.gameId}_opened',
      parameters: {
        'gameId': widget.gameId,
        'sessionId': _hostSessionId,
      },
      phone: _phone,
      userId: _uid,
    );
    _initWebView();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _phoneForDispose = _phone;
    _uidForDispose = _uid;
  }

  // Build the WebView, wire up the JS bridge, and load the HTML.
  void _initWebView() {
    // User-agent includes the participant id so the bridge JS can wipe stale
    // localStorage when a different participant launches on a shared device.
    final pid = _uid.isEmpty ? 'anon' : _uid;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('CCQApp/$pid')
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            // Inject the shared stylesheet and bridge shim, then restore progress.
            await _controller.runJavaScript(kCcqGameStyleInjectionJs);
            await _injectBridge();
            _loadGameState();
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            debugPrint('❌ ${widget.gameId} WebView Error: ${error.description}');
            // Drop the spinner so the player can still tap Home.
            if ((error.isForMainFrame ?? false) && mounted) {
              setState(() => _loading = false);
            }
            // Log to Firestore so load failures are visible to researchers.
            TelemetryHooks.logEvent(
              'webview_error',
              parameters: {
                'gameId': widget.gameId,
                'sessionId': _hostSessionId,
                'errorType': error.errorType?.name ?? 'unknown',
                'errorCode': error.errorCode,
                'description': error.description,
                'isMainFrame': error.isForMainFrame ?? false,
              },
              phone: _phone,
              userId: _uid,
            );
          },
        ),
      )
      // ---- JS BRIDGE MESSAGES ----
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (message) async {
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;

            // Custom handler first; bail if it claims the message.
            if (widget.onCustomBridgeMessage != null) {
              final handled =
                  await widget.onCustomBridgeMessage!(data, _externalController);
              if (handled) return;
            }

            switch (data['type']) {
              // Player renamed their walking buddy/pet - save the new name.
              case 'SET_DOG_NAME':
                await _updateBuddyName(data['name'] as String);
                break;
              // Player wants to leave - run the shared exit path.
              case 'GO_HOME':
                await _exitWithOptionalBpPrompt();
                break;
              // Game handed us its saved progress blob - store it for resume.
              case 'SAVE_STATE':
                await MovementHooks.saveGameStateJson(
                  uid: _uid,
                  gameId: widget.gameId,
                  stateJson: data['state'] as String,
                );
                break;
              // Player tapped "I'm done" in the game - finish the walk now.
              case 'FINISH_QUEST_DATA':
                await _endGame();
                break;
              // Player picked a distance and started walking. Set the target,
              // ask for GPS permission, then begin (or resume) tracking.
              case 'START_TRACKING':
                final incoming = (data['distance'] ?? widget.targetDistance)
                    .toDouble() as double;
                // Same target and some progress already? Treat as a resume.
                final shouldResume =
                    incoming == _targetDistance && _distanceWalked > 0;
                if (!shouldResume) _targetDistance = incoming;
                if (await _ensureLocationPermission()) {
                  await _startGame(resume: shouldResume);
                }
                break;
            }
          } catch (e) {
            debugPrint('❌ ${widget.gameId} JS Bridge Error: $e');
          }
        },
      )
      ..loadFlutterAsset(widget.htmlAsset);

    _externalController = TwineGameHostController._(
      webView: _controller,
      endGame: _endGame,
      goHome: () async {
        if (mounted) Navigator.of(context).pop();
      },
    );
  }

  // Inject ccq_bridge.js so window.CCQ exists. Skips if the game already has its own.
  Future<void> _injectBridge() async {
    try {
      final js = await rootBundle.loadString('assets/game/ccq_bridge.js');
      await _controller.runJavaScript(
        'if (!window.CCQ || typeof window.CCQ.goHome !== "function") {\n'
        '$js\n}',
      );
    } catch (e) {
      debugPrint('${widget.gameId} bridge inject failed: $e');
    }
  }

  Future<void> _updateBuddyName(String newName) async {
    if (_uid.isEmpty) return;
    setState(() => _currentBuddyName = newName);
    await ProfileHooks.updateBuddyName(_uid, newName);
  }

  // ---- RESUME LOGIC ----

  // Restore buddy name, weekly stats, and any saved walk progress after the page loads.
  Future<void> _loadGameState() async {
    final uid = _uid;

    if (uid.isEmpty) {
      _controller.runJavaScript("showPage('scene1');");
      return;
    }

    try {
      var hasOngoingWalk = false;

      // Push this week's completed quest count to the HTML for stats display.
      MovementHooks.fetchWeeklyQuestCount(uid: uid, gameId: widget.gameId)
          .then(_pushWeeklyQuestCount);

      // Restore the saved buddy name from the user profile.
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection(FirestorePaths.userData)
            .doc(uid)
            .get();
        if (userDoc.exists && userDoc.data() != null) {
          final data = userDoc.data()!;
          final saved = data['buddyName'] ?? data['dogName'];
          if (saved is String && saved.isNotEmpty) {
            _currentBuddyName = saved;
            _controller.runJavaScript(
              "if(typeof setBuddyName === 'function') { setBuddyName(${jsonEncode(saved)}); }",
            );
          }
        }
      } catch (_) {/* ignore - profile read is best-effort */}

      // Look up any saved "walk in progress" for this game.
      final gameDoc = await MovementHooks.fetchOngoingState(
        uid: uid,
        gameId: widget.gameId,
      );

      if (gameDoc.exists && gameDoc.data() != null) {
        final gData = gameDoc.data()!;

        if (gData.containsKey('gameState')) {
          _controller.runJavaScript(
            "if(typeof hydrateState === 'function') { hydrateState(${jsonEncode(gData['gameState'])}); }",
          );
        }

        // Validate saved walk data. Anything corrupt or zero means start fresh.
        final rawDistance = gData['ongoingDistance'];
        final rawTarget = gData['ongoingTarget'];
        final rawSessionId =
            gData['ongoingSessionId'] is String
                ? gData['ongoingSessionId'] as String
                : null;
        final lastCompletedSessionId =
            gData['lastCompletedSessionId'] is String
                ? gData['lastCompletedSessionId'] as String
                : null;
        final justCompletedInMemory =
            _justCompletedSessionByGame[widget.gameId];

        // A late GPS write can leave stale data after a completed walk.
        // If either "already done" marker matches, skip the resume.
        final sessionAlreadyCompleted = rawSessionId != null &&
            (rawSessionId == lastCompletedSessionId ||
                rawSessionId == justCompletedInMemory);

        // Only resume if numbers are real and the walk wasn't already done.
        final isValidResume = rawDistance is num &&
            rawTarget is num &&
            rawDistance > 0 &&
            rawTarget > 0 &&
            !rawDistance.isNaN &&
            !rawTarget.isNaN &&
            !sessionAlreadyCompleted;

        if (isValidResume) {
          // Restore where we left off.
          _distanceWalked = rawDistance.toDouble();
          _targetDistance = rawTarget.toDouble();
          _sessionId = rawSessionId;

          // Rebuild the path. Saved points may be GeoPoint or a {lat,lng} map.
          _pathCoordinates.clear();
          final rawPath = gData['ongoingPath'];
          if (rawPath is List) {
            for (final p in rawPath) {
              if (p is GeoPoint) {
                _pathCoordinates.add(p);
              } else if (p is Map &&
                  p['lat'] is num &&
                  p['lng'] is num) {
                _pathCoordinates.add(GeoPoint(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ));
              }
            }
          }

          // Resume tracking from where we left off.
          hasOngoingWalk = _sessionId != null;
          if (hasOngoingWalk) {
            _controller.runJavaScript(
              "if(typeof resumeWalk === 'function') { resumeWalk($_distanceWalked, $_targetDistance); }",
            );
            await _startGame(resume: true);
          }
        }
      }

      // showPage('scene1') was removed: SugarCube auto-renders the start passage,
      // and calling it again caused a visible flash on Dog Quest's welcome screen.
    } catch (e) {
      debugPrint('❌ ${widget.gameId} load error: $e');
    }
  }

  void _pushWeeklyQuestCount(int count) {
    _controller.runJavaScript(
      "if(typeof setWeeklyQuestCount === 'function') { setWeeklyQuestCount($count); }",
    );
  }

  // ---- GPS / LOCATION PERMISSION ----

  // Check location permission, prompting the player if needed. Returns true when ready.
  Future<bool> _ensureLocationPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await _showDialog(
          'Location Services Disabled',
          'Location services are disabled. Please enable them in your '
              'device settings so the game can track your movement.',
        );
        return false;
      }

      var permission = await Geolocator.checkPermission();
      while (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          final retry = await _showRetryDialog();
          if (!retry) return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        await _showDialog(
          'Location Permanently Denied',
          'Location permission is permanently denied. Open the app settings '
              'and enable location access to continue the game.',
        );
        return false;
      }

      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      debugPrint('Permission error: $e');
      return false;
    }
  }

  Future<void> _showDialog(String title, String body) async {
    if (!mounted) return; // don't touch UI if the screen is gone
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // "Location needed - try again?" Returns true if the player taps Try again.
  Future<bool> _showRetryDialog() async {
    if (!mounted) return false; // screen gone, nothing to ask
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Required'),
        content: Text(
          '${widget.gameTitle} needs location permission to complete the '
          'walk. Would you like to try again?',
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

  // ---- GPS TRACKING ----

  // Start (or resume) a walk: open the GPS feed, accumulate distance, and finish when done.
  Future<void> _startGame({bool resume = false}) async {
    final uid = _uid;
    if (uid.isEmpty) return;

    try {
      TelemetryHooks.logEvent(
        '${widget.gameId}_quest_started',
        parameters: {
          'gameId': widget.gameId,
          'sessionId': _hostSessionId,
          'movementSessionId': _sessionId,
          'target_distance': _targetDistance,
          'resumed': resume,
        },
        phone: _phone,
        userId: _uid,
      );

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      // New walk: generate a fresh id and reset counters.
      if (!resume || _sessionId == null) {
        _sessionId = MovementHooks.generateSessionId(widget.gameId);
        _distanceWalked = 0.0;
        _writeCount = 0;
        _pathCoordinates.clear();
      }

      _endingGame = false; // clear the "finishing" flag for this new walk

      setState(() {
        _isPlaying = true;
        _lastPosition = null;
      });

      if (resume) {
        _controller.runJavaScript(
          "if(typeof updateGameProgress === 'function') { updateGameProgress($_distanceWalked, $_targetDistance); }",
        );
      }

      // Each GPS fix measures the step from the previous point.
      _positionStream = LocationDispatcher.stream.listen((position) async {
        // If we're finishing or stopped, ignore late GPS updates.
        if (_endingGame || !_isPlaying) return;
        if (position.accuracy > 35.0) return; // too fuzzy to trust - skip it

        if (_lastPosition != null) {
          final distance = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );

          // Ignore jumps over 50m (GPS glitch, not a real step).
          // Re-baseline to this position but don't add the distance.
          if (distance > 50.0) {
            _lastPosition = position;
            return;
          }

          // Save to the cloud every 5th fix.
          _writeCount++;
          if (_writeCount % 5 == 0 &&
              _sessionId != null &&
              !_endingGame) {
            await MovementHooks.pushPing(
              uid: uid,
              sessionId: _sessionId!,
              gameId: widget.gameId,
              position: position,
              distanceWalked: _distanceWalked,
              targetDistance: _targetDistance,
              pathCoordinates: List.unmodifiable(_pathCoordinates),
            );
          }

          // Re-check: _endGame may have fired while we awaited the write.
          if (_endingGame || !_isPlaying) return;

          setState(() {
            _distanceWalked += distance;
            _pathCoordinates.add(
              GeoPoint(position.latitude, position.longitude),
            );
          });

          _controller.runJavaScript(
            "if(typeof updateGameProgress === 'function') { updateGameProgress($_distanceWalked, $_targetDistance); }",
          );

          if (_distanceWalked >= _targetDistance &&
              _isPlaying &&
              !_endingGame) {
            await _endGame();
          }
        }
        _lastPosition = position; // this fix becomes the baseline for the next
      });

      // Watchdog checks completion every 1.5s in case GPS goes quiet.
      _completionWatchdog?.cancel();
      _completionWatchdog = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) {
          if (!_isPlaying || _endingGame) {
            _completionWatchdog?.cancel();
            _completionWatchdog = null;
            return;
          }
          if (_distanceWalked >= _targetDistance) {
            _endGame();
          }
        },
      );
    } catch (e) {
      debugPrint('GPS error in ${widget.gameId}: $e');
    }
  }

  // ---- END OF GAME ----

  // Finish a walk: stop tracking, award points, save the result, grab vitals.
  // Guarded by _endingGame so it runs only once even if GPS + watchdog race.
  Future<void> _endGame() async {
    if (_endingGame) return; // already finishing - don't run twice
    _endingGame = true;
    _completionWatchdog?.cancel();
    _completionWatchdog = null;
    _positionStream?.cancel();

    final uid = _uid;
    if (uid.isEmpty) return;

    // Mark done so the launcher can show the feedback popup on the dashboard.
    GameCompletionSignal.markCompleted(widget.gameId);

    // Scale points by distance covered (max 1.0) so an early exit pays fairly.
    // A full walk clamps to 1.0 and earns full points.
    final fullPoints = widget.pointsCalculator(_targetDistance);
    final ratio = _targetDistance > 0
        ? (_distanceWalked / _targetDistance).clamp(0.0, 1.0)
        : 0.0;
    final pointsGained = (fullPoints * ratio).floor();
    final sessionId = _sessionId;

    TelemetryHooks.logEvent(
      '${widget.gameId}_quest_completed',
      parameters: {
        'gameId': widget.gameId,
        'sessionId': _hostSessionId,
        'movementSessionId': sessionId,
        'distance_walked': _distanceWalked.toInt(),
        'target_distance': _targetDistance.toInt(),
        'points_earned': pointsGained,
        'buddy_name': _currentBuddyName,
      },
      phone: _phone,
      userId: _uid,
    );

    setState(() => _isPlaying = false);

    try {
      if (sessionId != null) {
        // Mark done in memory BEFORE the end write, so a fast re-open can't
        // accidentally resume from stale data.
        _justCompletedSessionByGame[widget.gameId] = sessionId;

        // Save the finished walk (distance, points, path, etc.).
        await MovementHooks.endSession(
          uid: uid,
          sessionId: sessionId,
          gameId: widget.gameId,
          distanceWalked: _distanceWalked,
          targetDistance: _targetDistance,
          pointsEarned: pointsGained,
          buddyName: _currentBuddyName,
          pathCoordinates: List.unmodifiable(_pathCoordinates),
          completionEventName: '${widget.gameId}_completed',
        );
      }

      // Grab watch vitals in the background.
      unawaited(HealthHooks.logSnapshot(
        uid: uid,
        gameId: widget.gameId,
        sessionId: sessionId,
      ));
      _snapshotLogged = true; // remember we did it, so exit won't repeat it

      // Write a one-row summary for researchers.
      unawaited(_writeSessionSummary(
        exitReason: 'completed',
        distanceWalked: _distanceWalked.toInt(),
        pointsEarned: pointsGained,
        movementSessionId: sessionId,
      ));

      final completedDistance = _distanceWalked.toInt();

      setState(() {
        _distanceWalked = 0.0;
        _sessionId = null;
        _pathCoordinates.clear();
        _writeCount = 0;
      });

      if (mounted) {
        PointsHooks.applyIncrements(context, {
          'points': pointsGained,
          'totalDistance': completedDistance,
          'totalSessions': 1,
          'distanceTraveled': completedDistance,
          'measurementsTaken': 1,
        });

        // Play the celebration. BP is only collected in the Quiet Minute game now.
        _controller.runJavaScript('onQuestFinished($pointsGained)');

        final weeklyCount = await MovementHooks.fetchWeeklyQuestCount(
          uid: uid,
          gameId: widget.gameId,
        );
        if (mounted) _pushWeeklyQuestCount(weeklyCount); // re-check: awaited above
      }
    } catch (e) {
      debugPrint('❌ ${widget.gameId} sync error in _endGame: $e');
    }
  }

  // ---- EXIT & SUMMARY ----

  // Write a one-row session summary. Called at most once per visit.
  Future<void> _writeSessionSummary({
    required String exitReason,
    int distanceWalked = 0,
    int pointsEarned = 0,
    String? movementSessionId,
  }) async {
    if (_uid.isEmpty || _sessionSummaryWritten) return; // write it only once
    _sessionSummaryWritten = true;
    final endedAt = DateTime.now();
    final durationMs = endedAt.difference(_hostStartedAt).inMilliseconds;
    try {
      await GetIt.instance<OfflineQueue>().enqueue(PendingOp.set(
        '${FirestorePaths.userData}/$_uid/gameSessions/$_hostSessionId',
        {
          'sessionId': _hostSessionId,
          'userId': _uid,
          'gameId': widget.gameId,
          'gameTitle': widget.gameTitle,
          'hostType': 'TwineGameHost',
          'startedAt': OfflineFieldValue.timestampFrom(_hostStartedAt),
          'endedAt': OfflineFieldValue.nowTimestamp(),
          'durationMs': durationMs,
          'exitReason': exitReason,
          'distanceWalked': distanceWalked,
          'pointsEarned': pointsEarned,
          if (movementSessionId != null)
            'movementSessionId': movementSessionId,
        },
      ));
    } catch (e) {
      debugPrint('TwineGameHost session summary write failed: $e');
    }
  }

  // The one exit path (home button, back arrow, back gesture).
  // If they leave before finishing, still grab vitals and write the summary.
  Future<void> _exitWithOptionalBpPrompt() async {
    if (!mounted) return; // screen already gone
    if (!_snapshotLogged) {
      unawaited(HealthHooks.logSnapshot(
        uid: _uid,
        gameId: widget.gameId,
        sessionId: _hostSessionId,
      ));
      _snapshotLogged = true;
    }
    // Guard inside _writeSessionSummary prevents a second write if _endGame already ran.
    unawaited(_writeSessionSummary(
      exitReason: 'exited_in_progress',
      distanceWalked: _distanceWalked.toInt(),
    ));
    // Pop all the way to the first route so exit always lands on the dashboard.
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // Ask "save and exit?" only if a walk is actually in progress.
  Future<bool> _confirmExit() async {
    if (!_isPlaying || _distanceWalked <= 0 || _sessionId == null) {
      return true; // nothing in progress - leaving is fine
    }
    if (!mounted) return true;
    return _showExitDialog();
  }

  // Show the "leave the walk?" dialog. Saves progress if they choose to exit.
  Future<bool> _showExitDialog() async {
    final ctx = context;
    final shouldLeave = widget.confirmExitDialog != null
        // ignore: use_build_context_synchronously
        ? await widget.confirmExitDialog!(ctx)
        : await showDialog<bool>(
            // ignore: use_build_context_synchronously
            context: ctx,
            builder: (context) => AlertDialog(
              title: Text('Leave ${widget.gameTitle}?'),
              content: const Text(
                'You have an active walk in progress. Do you want to save '
                'and exit?',
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

    // Save progress so the walk can be resumed next time.
    if (shouldLeave == true && _uid.isNotEmpty && _sessionId != null) {
      await MovementHooks.saveOngoingState(
        uid: _uid,
        gameId: widget.gameId,
        sessionId: _sessionId!,
        distanceWalked: _distanceWalked,
        targetDistance: _targetDistance,
        pathCoordinates: List.unmodifiable(_pathCoordinates),
      );
    }

    return shouldLeave == true;
  }

  @override
  void dispose() {
    _completionWatchdog?.cancel();
    _completionWatchdog = null;
    _positionStream?.cancel();
    SessionManager.endGame();
    try {
      TelemetryHooks.logEvent(
        '${widget.gameId}_closed',
        parameters: {
          'gameId': widget.gameId,
          'sessionId': _hostSessionId,
        },
        phone: _phoneForDispose,
        userId: _uidForDispose,
      );
    } catch (e) {
      debugPrint('Error logging dispose for ${widget.gameId}: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No Flutter AppBar: the Twine HTML renders its own header and the burger
    // menu handles "Go to dashboard". Removing the AppBar gives the game the
    // full screen height. Exit is also covered by PopScope and the Home button.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _confirmExit();
        if (shouldPop && context.mounted) {
          await _exitWithOptionalBpPrompt();
        }
      },
      child: Scaffold(
        // Dark navy fills behind the status bar. SafeArea was removed to avoid
        // an extra gap between the status bar and the game's own header.
        backgroundColor: const Color(0xFF1a1b2e),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: WebViewWidget(controller: _controller)),
            // Spinner overlay while the HTML loads. Removed when onPageFinished fires.
            if (_loading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF4A1D6C)),
                        SizedBox(height: 16),
                        Text(
                          'Loading game...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4A1D6C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Always-visible Home button, even before the in-game menu has loaded.
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Home',
                      icon: const Icon(Icons.home_rounded, color: Colors.white),
                      onPressed: () async {
                        final shouldPop = await _confirmExit();
                        if (shouldPop && context.mounted) {
                          await _exitWithOptionalBpPrompt();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
