import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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

// TwineGameHost - runs a "walk somewhere" HTML game inside the app.
//
// The game is a web page (Twine) shown in a WebView. This file is the glue:
// it tracks your GPS walk, tells the game how far you've gone, and saves the
// result. The web page and Dart talk to each other by passing little text
// messages (the "bridge"). One reusable host so every walking game shares the
// same GPS, save, and finish logic instead of copy-pasting it.

// Shape of an optional "let a specific game handle this message itself" hook.
// Return true = "I dealt with it, stop here"; false = "not mine, carry on".
/// Signature for game-specific bridge message handlers. Return `true` if the
/// message was handled (no further processing); `false` to fall through to
/// the host's default switch (or be silently ignored).
typedef OnTwineBridgeMessage = Future<bool> Function(
  Map<String, dynamic> data,
  TwineGameHostController controller,
);

// How many points a finished walk is worth. Longer target = more points.
/// Calculates how many points to award on completion. Default: 30 / 60 / 100
/// for ≤500m / ≤1000m / >1000m targets. Override per game if you want
/// different scoring.
typedef PointsCalculator = int Function(double targetDistance);

// The default scoring rule if a game doesn't supply its own.
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
// The widget you drop into a screen. Just holds the settings for one game
// (its id, title, HTML file, walk distance). The real work lives in the State.
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

// ---- CONTROLLER ----

/// Lightweight controller exposed to [OnTwineBridgeMessage] callbacks so
/// game-specific handlers can call into the host's WebView and lifecycle.
// A small "remote control" we hand to custom message handlers so they can
// poke the web page, end the game, or go home - without seeing the whole host.
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

// The brain of the host. Holds all the live state for one play and does the
// GPS tracking, saving, resuming, and finishing.
class _TwineGameHostState extends State<TwineGameHost> {
  // ---- STATE (the live values for this one play) ----
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

  // Watchdog = a repeating timer that double-checks "have we hit the target
  // yet?" even when GPS goes quiet, so the walk can still finish.
  // Periodic re-check of the completion threshold so the quest still
  // completes when the position stream goes quiet (emulator route ended,
  // accuracy-filtered fix, GPS lost lock, etc.).
  Timer? _completionWatchdog;

  // "We're finishing now" flag. Two things (the watchdog and a GPS update) can
  // both try to end the game at once - this makes sure end runs only once.
  // Re-entry guard: a watchdog tick + a position-stream callback can race
  // each other, and an in-flight position event can also fire after
  // _endGame() started. This flag short-circuits all of them.
  bool _endingGame = false;

  // Remembers "this walk already finished" so we never accidentally resume it.
  // Tombstone = a marker that says "done, don't bring it back". Kept per game
  // and outside the State so it survives leaving and re-opening the screen.
  /// Per-gameId record of the most recently completed sessionId, kept at
  /// class level so it survives navigation within an app session (the
  /// State is destroyed on pop). Pairs with the Firestore-side
  /// `lastCompletedSessionId` tombstone written by [MovementHooks.endSession]
  /// to defeat a race where a periodic GPS write lands AFTER the end-game's
  /// delete batch in OfflineQueue replay, leaving stale `ongoing*` fields.
  static final Map<String, String> _justCompletedSessionByGame = {};

  // Id for this whole visit to the screen (one "open"), tagged on every event
  // so researchers can group them. Different from _sessionId (one walk).
  /// Stamped onto every telemetry event coming out of this host instance
  /// (open, quest_started, quest_completed, closed, webview_error). One
  /// "host session" = one open of the Dog Walking screen, regardless of
  /// how many walks the player started/resumed inside it. Distinct from
  /// the movement [_sessionId] (per-walk, lives in MovementHooks writes).
  late final String _hostSessionId;

  // When this visit started, so we can record how long they played.
  /// Wall-clock start of this host session - pairs with `_hostSessionId`
  /// to compute the per-play duration written into the gameSessions
  /// summary doc on exit.
  late final DateTime _hostStartedAt;

  // Make sure the "one summary row per visit" write happens only once, even
  // if the player both finishes a walk and then backs out.
  /// One-shot guard so the gameSessions summary is written exactly
  /// once per host instance regardless of how many exit paths fire
  /// (completion → _endGame, then user backs out → _exitWithOptionalBpPrompt).
  bool _sessionSummaryWritten = false;

  // Snapshot = a one-time grab of watch vitals (heart rate, etc.). This flag
  // stops us grabbing it twice if the player finishes AND then backs out.
  /// True once a HealthKit snapshot has been logged for this host
  /// session (either via [_endGame] on quest completion or via the
  /// fallback in [_exitWithOptionalBpPrompt] on early exit). Prevents a
  /// double snapshot when a player completes a walk AND then backs out.
  bool _snapshotLogged = false;

  // Quick shortcuts to the logged-in user's phone + id from shared app state.
  String get _phone =>
      Provider.of<UserDataProvider>(context, listen: false).phone;
  String get _uid =>
      Provider.of<UserDataProvider>(context, listen: false).uid;

  // ---- SETUP / LIFECYCLE ----

  // Runs once when the screen opens: set up ids, tell the app a game started,
  // log the "opened" event, and build the WebView.
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

  // Builds the WebView that shows the game, and wires up the two-way message
  // bridge so the web page and Dart can talk. Also loads the game's HTML file.
  void _initWebView() {
    // Tag the user agent with the current participant id so the
    // inlined bridge JS can wipe stale per-user localStorage when
    // a different participant launches a game on a shared device.
    // See twine_questionnaire_host.dart for the rationale.
    final pid = _uid.isEmpty ? 'anon' : _uid;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('CCQApp/$pid')
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
      // ---- JS BRIDGE MESSAGES ----
      // The web page sends little JSON messages here; we act on each "type".
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

  // Save the buddy's new name and update the screen to show it.
  Future<void> _updateBuddyName(String newName) async {
    if (_uid.isEmpty) return;
    setState(() => _currentBuddyName = newName);
    await ProfileHooks.updateBuddyName(_uid, newName);
  }

  // ---- RESUME LOGIC ----

  // Runs when the game page finishes loading. Restores the buddy name, this
  // week's stats, and - if a valid unfinished walk was saved - picks it back up.
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

        // WHY: the saved walk might actually be a finished one that left
        // stale leftovers behind (a late GPS save landed after the delete).
        // If either "already done" marker matches, don't resume it.
        final sessionAlreadyCompleted = rawSessionId != null &&
            (rawSessionId == lastCompletedSessionId ||
                rawSessionId == justCompletedInMemory);

        // Only resume if the saved numbers look real (positive, not garbage)
        // and the walk wasn't already finished.
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

          // Rebuild the walked trail. Saved points may be in two formats, so
          // read both shapes carefully and skip anything odd.
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

          // Tell the game to show the resumed progress, then re-start tracking.
          hasOngoingWalk = _sessionId != null;
          if (hasOngoingWalk) {
            _controller.runJavaScript(
              "if(typeof resumeWalk === 'function') { resumeWalk($_distanceWalked, $_targetDistance); }",
            );
            await _startGame(resume: true);
          }
        }
      }

      // Removed: `_controller.runJavaScript("showPage('scene1');")`.
      // That line was a leftover from when games were legacy single-
      // page HTMLs with display:none scene toggles. Now that every
      // game is Twine, SugarCube auto-renders the configured start
      // passage on load - calling showPage('scene1') after that just
      // forced a second render of the same passage, which Dog Quest's
      // welcome scene flashed visibly because it was its first paint.
      // Resume case still uses resumeWalk above; no other game has
      // ever defined showPage so the guarded call was a no-op there.
    } catch (e) {
      debugPrint('❌ ${widget.gameId} load error: $e');
    }
  }

  // Tell the game page how many quests were finished this week (for stats).
  void _pushWeeklyQuestCount(int count) {
    _controller.runJavaScript(
      "if(typeof setWeeklyQuestCount === 'function') { setWeeklyQuestCount($count); }",
    );
  }

  // ---- GPS / LOCATION PERMISSION ----

  // Make sure location is on and we're allowed to use it. Nudges the player
  // with dialogs if not. Returns true only when we can actually track.
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

  // Simple pop-up with a title, a message, and an OK button.
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

  // "Location needed - try again?" pop-up. Returns true if they tap Try again.
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

  // Starts (or resumes) a walk: opens the GPS feed, adds up distance as you
  // move, saves progress now and then, and finishes when you hit the target.
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

      // Fresh walk (not a resume): make a new walk id and zero everything out.
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

      // Listen to the live GPS feed. Each new fix = one step to measure.
      _positionStream = LocationDispatcher.stream.listen((position) async {
        // If we're finishing or stopped, ignore late GPS updates.
        if (_endingGame || !_isPlaying) return;
        if (position.accuracy > 35.0) return; // too fuzzy to trust - skip it

        if (_lastPosition != null) {
          // How far since the last point.
          final distance = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );

          // Reject implausible jumps. Fixes arrive ~1s apart; >50m in that
          // window is ~180km/h - a GPS glitch, not a walk. Without this cap a
          // single spurious fix could add hundreds of metres and complete the
          // quest on its own. Re-baseline to this position but don't credit
          // the jump. (custom_walk_game applies the same guard.)
          if (distance > 50.0) {
            _lastPosition = position;
            return;
          }

          // Save to the cloud only every 5th fix to avoid spamming writes.
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

          // Final guard before any state mutation / JS injection - _endGame
          // may have flipped _endingGame while we were on an await.
          if (_endingGame || !_isPlaying) return;

          // Add the step to the total and remember this point on the trail.
          setState(() {
            _distanceWalked += distance;
            _pathCoordinates.add(
              GeoPoint(position.latitude, position.longitude),
            );
          });

          // Show the new progress in the game.
          _controller.runJavaScript(
            "if(typeof updateGameProgress === 'function') { updateGameProgress($_distanceWalked, $_targetDistance); }",
          );

          // Reached the goal? Finish the walk.
          if (_distanceWalked >= _targetDistance &&
              _isPlaying &&
              !_endingGame) {
            await _endGame();
          }
        }
        _lastPosition = position; // this fix becomes the baseline for the next
      });

      // Watchdog: every 1.5s, double-check if we've hit the goal, in case GPS
      // updates stopped coming in. Cancels itself once the walk ends.
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

  // ---- END OF GAME (race-safe) ----

  // Wraps up a walk: stops tracking, works out points, saves the result, grabs
  // vitals, updates the score, and plays the celebration. Guarded so it runs
  // once even if the GPS update and the watchdog both call it together.
  Future<void> _endGame() async {
    if (_endingGame) return; // already finishing - don't run twice
    _endingGame = true;
    // Stop the timer and GPS feed so nothing keeps adding distance.
    _completionWatchdog?.cancel();
    _completionWatchdog = null;
    _positionStream?.cancel();

    final uid = _uid;
    if (uid.isEmpty) return;

    // Partial-walk credit: scale the full reward by how far the participant
    // actually walked, so a walk ended early (via the bridge's
    // FINISH_QUEST_DATA "I'm done" path) is credited proportionally instead
    // of paying full points for zero movement. A completed walk has
    // _distanceWalked >= _targetDistance, so the ratio clamps to 1.0 and full
    // walks are unaffected. Floored so truncation can never round a partial
    // walk up to full. Mirrors custom_walk_game's model.
    // Points = full reward scaled by how far you actually got (max 1.0), so
    // ending early pays fairly and a finished walk still pays full.
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
        // WHY: mark this walk "done" in memory BEFORE saving the end writes,
        // so if the player leaves and comes back fast, resume won't pick up
        // stale leftovers from a save that lands late.
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

      // Grab watch vitals in the background while the celebration plays.
      unawaited(HealthHooks.logSnapshot(
        uid: uid,
        gameId: widget.gameId,
        sessionId: sessionId,
      ));
      _snapshotLogged = true; // remember we did it, so exit won't repeat it

      // Write the one-row "this play happened" summary for researchers.
      unawaited(_writeSessionSummary(
        exitReason: 'completed',
        distanceWalked: _distanceWalked.toInt(),
        pointsEarned: pointsGained,
        movementSessionId: sessionId,
      ));

      final completedDistance = _distanceWalked.toInt();

      // Reset the live walk values now that it's saved.
      setState(() {
        _distanceWalked = 0.0;
        _sessionId = null;
        _pathCoordinates.clear();
        _writeCount = 0;
      });

      // mounted = screen still on-screen. Only touch UI/score if so.
      if (mounted) {
        // Add points and stats to the player's totals.
        PointsHooks.applyIncrements(context, {
          'points': pointsGained,
          'totalDistance': completedDistance,
          'totalSessions': 1,
          'distanceTraveled': completedDistance,
          'measurementsTaken': 1,
        });

        // Run the in-game celebration scene. No external BP prompt -
        // BP is collected only in the Quiet Minute game now (relaxed
        // state per the research protocol). HealthKit snapshot still
        // fires after every game (see HealthHooks.logSnapshot above).
        _controller.runJavaScript('onQuestFinished($pointsGained)');

        // Refresh this week's count shown in the game.
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

  // Save one summary row for this visit (when, how long, why it ended, points).
  // Guarded so it's written only once per visit.
  /// Write a gameSessions summary doc for this host session - netguage
  /// CheckData-equivalent. One row per play of one game by one user.
  /// Joins to telemetry events, MovementHooks LocationData/CheckData,
  /// and any HealthKit snapshots by `sessionId` (well, `_hostSessionId`
  /// - the per-walk movement sessionId is recorded as a separate
  /// `movementSessionId` field for movement games that completed).
  /// Mirrors `TwineQuestionnaireHost._writeSessionSummary` so a single
  /// query against `userData/{uid}/gameSessions` enumerates every play
  /// of every game type.
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

  /// Single exit path used by GO_HOME, the leading back arrow, and the
  /// PopScope back-button handler. If the player exits before completing
  /// a walk (so [_endGame] never fired), we still log a HealthKit snapshot
  /// here so researchers don't lose wearable data when participants
  /// abandon mid-walk. Guarded by [_snapshotLogged] to prevent a double
  /// snapshot when a completion + back-out happen in sequence.
  // The one way out (home button, back arrow, back gesture). If they leave
  // before finishing, still grab vitals + write the summary, then pop back.
  Future<void> _exitWithOptionalBpPrompt() async {
    if (!mounted) return; // screen already gone
    // Only grab vitals if a finished walk didn't already do it.
    if (!_snapshotLogged) {
      unawaited(HealthHooks.logSnapshot(
        uid: _uid,
        gameId: widget.gameId,
        sessionId: _hostSessionId,
      ));
      _snapshotLogged = true;
    }
    // Session summary on the no-completion exit path. The
    // `_sessionSummaryWritten` guard inside ensures this no-ops if
    // `_endGame` already wrote one for a completed walk.
    unawaited(_writeSessionSummary(
      exitReason: 'exited_in_progress',
      distanceWalked: _distanceWalked.toInt(),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  // Should we ask "save and exit?" before leaving? Only if a real walk is in
  // progress; otherwise just let them go.
  Future<bool> _confirmExit() async {
    if (!_isPlaying || _distanceWalked <= 0 || _sessionId == null) {
      return true; // nothing in progress - leaving is fine
    }
    if (!mounted) return true;
    return _showExitDialog();
  }

  // Show the "leave the walk?" pop-up. If they choose to exit, save the walk
  // so it can be resumed later. Returns true when they want to leave.
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

    // Leaving mid-walk: save progress so we can pick it up next time.
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

  // Runs when the screen is torn down: stop the timer and GPS feed, tell the
  // app the game ended, and log a "closed" event. Always clean up here.
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

  // Builds the screen: basically just the full-screen WebView (the game). The
  // PopScope catches the back gesture so we can ask before leaving mid-walk.
  @override
  Widget build(BuildContext context) {
    // No Flutter AppBar - the Twine HTMLs render their own header
    // inside the WebView (`<div class="header">`), and the burger menu
    // auto-injected by `ccq_bridge.js` provides "Go to dashboard".
    // Stacking the native AppBar on top produced a redundant double-
    // header eating ~110px of vertical space before the game content
    // started. Removing it gives the game the full viewport.
    //
    // Exit paths still covered:
    //   • Burger menu → "Go to dashboard"
    //   • Android system back gesture (PopScope below)
    //   • In-game completion buttons via CCQ.goHome
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
        // Dark navy fallback for any inset Android may carve out for
        // the system status bar. Most Android builds already put the
        // status bar ABOVE the activity's content area (opaque), so
        // content starts below the bar with no inset needed.
        // Earlier the WebView was wrapped in SafeArea(top:true) which
        // added EXTRA padding on top of that - visually a stranded
        // band of Scaffold bg between the OS status bar and the
        // game's own header. Without SafeArea, the WebView fills all
        // the way up so the game header sits directly under the
        // status bar with no seam.
        backgroundColor: const Color(0xFF1a1b2e),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
