import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/services/location_service.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';

/// Signature for game-specific bridge message handlers. Return `true` if the
/// message was handled (no further processing); `false` to fall through to
/// the host's default switch (or be silently ignored).
typedef OnTwineBridgeMessage = Future<bool> Function(
  Map<String, dynamic> data,
  TwineGameHostController controller,
);

/// Calculates how many points to award on completion. Default: 30 / 60 / 100
/// for ≤500m / ≤1000m / >1000m targets. Override per game if you want
/// different scoring.
typedef PointsCalculator = int Function(double targetDistance);

int _defaultPointsCalculator(double target) =>
    target <= 500 ? 30 : (target <= 1000 ? 60 : 100);

/// Generic, reusable host for any GPS-tracked Twine HTML game.
///
/// Replaces the ~750-line copy-paste pattern in `dog_quest.dart`. New games
/// only need to:
///   1. Drop a `.html` file into `assets/game/` (declare it in pubspec.yaml).
///   2. Wrap [TwineGameHost] from a thin `StatelessWidget`:
///
///        return TwineGameHost(
///          gameId: 'salt_sludge',
///          gameTitle: 'Salt Sludge',
///          htmlAsset: 'assets/game/salt_sludge.html',
///          targetDistance: 500,
///        );
///
/// Behaviors handled internally (matches `dog_quest.dart`'s polished
/// implementation):
///   * WebView setup with `FlutterBridge` JavaScript channel.
///   * Standard bridge messages: `SET_DOG_NAME`, `GO_HOME`, `SAVE_STATE`,
///     `FINISH_QUEST_DATA`, `START_TRACKING`.
///   * Position-stream subscription with accuracy filter (>35 m rejected).
///   * Periodic GPS write (every 5 fixes) via [MovementHooks.pushPing].
///   * Re-entry-safe end-game with [MovementHooks.endSession] writes.
///   * Watchdog Timer that re-evaluates the completion threshold every
///     1.5 s (handles GPS-quiet edge cases).
///   * Resume logic with strict validation of cached `ongoing*` fields.
///   * Quest-difficulty title/desc lookup on resume via `resumeWalk` JS.
///   * Optimistic local point bump on completion via [PointsHooks].
///   * Lifecycle telemetry via [TelemetryHooks]:
///     `{gameId}_opened`, `{gameId}_quest_started`,
///     `{gameId}_quest_completed`, `{gameId}_closed`.
///   * Exit-confirmation dialog when player has unfinished progress, and
///     resume-state save via [MovementHooks.saveOngoingState].
///
/// Game-specific behavior (custom bridge messages, custom completion JS,
/// custom AppBar styling) is exposed via constructor parameters.
class TwineGameHost extends StatefulWidget {
  /// Stable identifier for this game (e.g. `'dog_quest'`). Used as the
  /// `game` field on Firestore session docs and as the doc ID for the
  /// `gameStates/{gameId}` resume slot. MUST be unique across games.
  final String gameId;

  /// User-facing title shown in the AppBar (e.g. `'Dog Walking'`).
  final String gameTitle;

  /// Asset path to the Twine HTML to load (e.g.
  /// `'assets/game/dog_quest.html'`). Must be declared in `pubspec.yaml`.
  final String htmlAsset;

  /// Quest target distance in meters. May be overridden by the HTML's
  /// `START_TRACKING` bridge message (so a Twine page with quest-difficulty
  /// buttons can choose 500 / 1000 / 1500). Also overridden by the resume
  /// flow if a saved `ongoingTarget` is found.
  final double targetDistance;

  /// AppBar background color. Defaults to a deep purple matching dog_quest.
  final Color appBarColor;

  /// Optional override for the points-on-completion formula.
  final PointsCalculator pointsCalculator;

  /// Optional handler invoked BEFORE the host's default switch on each
  /// inbound JS bridge message. Return `true` to claim the message; `false`
  /// to fall through. Use for game-specific message types (e.g. trivia
  /// games may add `SUBMIT_ANSWER`).
  final OnTwineBridgeMessage? onCustomBridgeMessage;

  /// Optional confirm-exit prompt customization. If null, the default
  /// "save and exit" dialog is shown when the player tries to leave with
  /// progress > 0.
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

/// Lightweight controller exposed to [OnTwineBridgeMessage] callbacks so
/// game-specific handlers can call into the host's WebView and lifecycle.
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

class _TwineGameHostState extends State<TwineGameHost> {
  late final WebViewController _controller;
  late TwineGameHostController _externalController;

  bool _isPlaying = false;
  double _distanceWalked = 0.0;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStream;
  final List<GeoPoint> _pathCoordinates = [];
  late double _targetDistance;
  int _writeCount = 0;
  String? _sessionId;
  String _currentBuddyName = 'Buddy';

  // Periodic re-check of the completion threshold so the quest still
  // completes when the position stream goes quiet (emulator route ended,
  // accuracy-filtered fix, GPS lost lock, etc.).
  Timer? _completionWatchdog;

  // Re-entry guard: a watchdog tick + a position-stream callback can race
  // each other, and an in-flight position event can also fire after
  // _endGame() started. This flag short-circuits all of them.
  bool _endingGame = false;

  /// Per-gameId record of the most recently completed sessionId, kept at
  /// class level so it survives navigation within an app session (the
  /// State is destroyed on pop). Pairs with the Firestore-side
  /// `lastCompletedSessionId` tombstone written by [MovementHooks.endSession]
  /// to defeat a race where a periodic GPS write lands AFTER the end-game's
  /// delete batch in OfflineQueue replay, leaving stale `ongoing*` fields.
  static final Map<String, String> _justCompletedSessionByGame = {};

  /// Stamped onto every telemetry event coming out of this host instance
  /// (open, quest_started, quest_completed, closed, webview_error). One
  /// "host session" = one open of the Dog Walking screen, regardless of
  /// how many walks the player started/resumed inside it. Distinct from
  /// the movement [_sessionId] (per-walk, lives in MovementHooks writes).
  late final String _hostSessionId;

  /// True once a HealthKit snapshot has been logged for this host
  /// session (either via [_endGame] on quest completion or via the
  /// fallback in [_exitWithOptionalBpPrompt] on early exit). Prevents a
  /// double snapshot when a player completes a walk AND then backs out.
  bool _snapshotLogged = false;

  String get _phone =>
      Provider.of<UserDataProvider>(context, listen: false).phone;
  String get _uid =>
      Provider.of<UserDataProvider>(context, listen: false).uid;

  @override
  void initState() {
    super.initState();
    _targetDistance = widget.targetDistance;
    _hostSessionId =
        '${widget.gameId}_host_${DateTime.now().millisecondsSinceEpoch}';
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

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _loadGameState(),
          onWebResourceError: (error) {
            debugPrint('❌ ${widget.gameId} WebView Error: ${error.description}');
            // Report to Firestore so a failed movement-game load isn't
            // invisible to researchers. Mirrors the questionnaire host.
            // Uses _hostSessionId (always set since initState) rather than
            // the movement _sessionId (null until _startGame fires).
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
              case 'SET_DOG_NAME':
                await _updateBuddyName(data['name'] as String);
                break;
              case 'GO_HOME':
                await _exitWithOptionalBpPrompt();
                break;
              case 'SAVE_STATE':
                await MovementHooks.saveGameStateJson(
                  uid: _uid,
                  gameId: widget.gameId,
                  stateJson: data['state'] as String,
                );
                break;
              case 'FINISH_QUEST_DATA':
                await _endGame();
                break;
              case 'START_TRACKING':
                final incoming = (data['distance'] ?? widget.targetDistance)
                    .toDouble() as double;
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

  Future<void> _updateBuddyName(String newName) async {
    if (_uid.isEmpty) return;
    setState(() => _currentBuddyName = newName);
    await ProfileHooks.updateBuddyName(_uid, newName);
  }

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
            .collection('userData')
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
      } catch (_) {/* ignore — profile read is best-effort */}

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

        // Strict validation. Anything half-synced or corrupt → start fresh.
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

        // The doc looks like it has an in-progress session, but if either
        // the Firestore tombstone OR the in-memory just-completed cache
        // says this session was already finished, the `ongoing*` fields
        // are leftover residue from a periodic write that landed AFTER
        // the end-game delete batch. Skip the resume.
        final sessionAlreadyCompleted = rawSessionId != null &&
            (rawSessionId == lastCompletedSessionId ||
                rawSessionId == justCompletedInMemory);

        final isValidResume = rawDistance is num &&
            rawTarget is num &&
            rawDistance > 0 &&
            rawTarget > 0 &&
            !rawDistance.isNaN &&
            !rawTarget.isNaN &&
            !sessionAlreadyCompleted;

        if (isValidResume) {
          _distanceWalked = rawDistance.toDouble();
          _targetDistance = rawTarget.toDouble();
          _sessionId = rawSessionId;

          // Path can be GeoPoint OR encoded {__type, lat, lng} markers (from
          // a previous queue replay). Decode defensively.
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

          hasOngoingWalk = _sessionId != null;
          if (hasOngoingWalk) {
            _controller.runJavaScript(
              "if(typeof resumeWalk === 'function') { resumeWalk($_distanceWalked, $_targetDistance); }",
            );
            await _startGame(resume: true);
          }
        }
      }

      if (!hasOngoingWalk) {
        _controller.runJavaScript("showPage('scene1');");
      }
    } catch (e) {
      debugPrint('❌ ${widget.gameId} load error: $e');
      _controller.runJavaScript("showPage('scene1');");
    }
  }

  void _pushWeeklyQuestCount(int count) {
    _controller.runJavaScript(
      "if(typeof setWeeklyQuestCount === 'function') { setWeeklyQuestCount($count); }",
    );
  }

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
    if (!mounted) return;
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

  Future<bool> _showRetryDialog() async {
    if (!mounted) return false;
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

      if (!resume || _sessionId == null) {
        _sessionId = MovementHooks.generateSessionId(widget.gameId);
        _distanceWalked = 0.0;
        _writeCount = 0;
        _pathCoordinates.clear();
      }

      _endingGame = false;

      setState(() {
        _isPlaying = true;
        _lastPosition = null;
      });

      if (resume) {
        _controller.runJavaScript(
          "if(typeof updateGameProgress === 'function') { updateGameProgress($_distanceWalked, $_targetDistance); }",
        );
      }

      _positionStream = LocationDispatcher.stream.listen((position) async {
        // Race-safety: bail on any in-flight event after _endGame started.
        if (_endingGame || !_isPlaying) return;
        if (position.accuracy > 35.0) return;

        if (_lastPosition != null) {
          final distance = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );

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

          // Final guard before any state mutation / JS injection — _endGame
          // may have flipped _endingGame while we were on an await.
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
        _lastPosition = position;
      });

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

  Future<void> _endGame() async {
    if (_endingGame) return;
    _endingGame = true;
    _completionWatchdog?.cancel();
    _completionWatchdog = null;
    _positionStream?.cancel();

    final uid = _uid;
    if (uid.isEmpty) return;

    final pointsGained = widget.pointsCalculator(_targetDistance);
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
        // Mark the just-completed session in the in-memory cache BEFORE
        // queueing the end-game writes. If the user navigates away and
        // back before sync fully drains, _loadGameState's resume check
        // will see this match and skip resuming on stale residue.
        _justCompletedSessionByGame[widget.gameId] = sessionId;

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

      // Fire-and-forget HealthKit snapshot — runs while the celebration
      // scene plays. Independent of the BP prompt's once-per-day gate;
      // researchers get vitals data after every game end.
      unawaited(HealthHooks.logSnapshot(
        uid: uid,
        gameId: widget.gameId,
        sessionId: sessionId,
      ));
      _snapshotLogged = true;

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

        // Run the in-game celebration scene. No external BP prompt —
        // BP is collected only in the Quiet Minute game now (relaxed
        // state per the research protocol). HealthKit snapshot still
        // fires after every game (see HealthHooks.logSnapshot above).
        _controller.runJavaScript('onQuestFinished($pointsGained)');

        final weeklyCount = await MovementHooks.fetchWeeklyQuestCount(
          uid: uid,
          gameId: widget.gameId,
        );
        if (mounted) _pushWeeklyQuestCount(weeklyCount);
      }
    } catch (e) {
      debugPrint('❌ ${widget.gameId} sync error in _endGame: $e');
    }
  }

  /// Single exit path used by GO_HOME, the leading back arrow, and the
  /// PopScope back-button handler. If the player exits before completing
  /// a walk (so [_endGame] never fired), we still log a HealthKit snapshot
  /// here so researchers don't lose wearable data when participants
  /// abandon mid-walk. Guarded by [_snapshotLogged] to prevent a double
  /// snapshot when a completion + back-out happen in sequence.
  Future<void> _exitWithOptionalBpPrompt() async {
    if (!mounted) return;
    if (!_snapshotLogged) {
      unawaited(HealthHooks.logSnapshot(
        uid: _uid,
        gameId: widget.gameId,
        sessionId: _hostSessionId,
      ));
      _snapshotLogged = true;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmExit() async {
    if (!_isPlaying || _distanceWalked <= 0 || _sessionId == null) {
      return true;
    }
    if (!mounted) return true;
    return _showExitDialog();
  }

  /// Wrapped in its own method so the BuildContext is fresh on entry. The
  /// `mounted` check in [_confirmExit] guards the only async-gap path.
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
        phone: _phone,
        userId: _uid,
      );
    } catch (e) {
      debugPrint('Error logging dispose for ${widget.gameId}: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: widget.appBarColor,
          elevation: 0,
          centerTitle: false,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            widget.gameTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldClose = await _confirmExit();
              if (shouldClose && context.mounted) {
                await _exitWithOptionalBpPrompt();
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
