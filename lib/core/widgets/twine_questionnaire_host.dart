import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';

/// Lightweight WebView host for **non-movement** Twine pages — surveys,
/// questionnaires, the control game (#8 in the work plan), reading-only
/// educational pages, etc.
///
/// Sibling of the GPS-tracked [TwineGameHost]. Both expose the same
/// `FlutterBridge` JS channel and `ccq_bridge.js` shim, but this host
/// strips out everything specific to a movement quest:
///
///   * No Geolocator / position stream / accuracy filter.
///   * No `MovementHooks.pushPing` / `endSession` writes.
///   * No watchdog Timer or resume-mid-walk plumbing.
///   * No `Movement Data` Firestore docs are produced — submissions go
///     to `surveys/{surveyId}/responses/{auto}` via [SurveyHooks].
///
/// Standard bridge messages handled:
///
/// | message              | action                                         |
/// |----------------------|------------------------------------------------|
/// | `GO_HOME`            | Pop back to the previous route.                |
/// | `SAVE_STATE`         | `MovementHooks.saveGameStateJson` (Twine state).|
/// | `SUBMIT_RESPONSE`    | `SurveyHooks.submitResponse` + optimistic UI.  |
/// | `TELEMETRY`          | Custom-event passthrough to [TelemetryHooks].  |
/// | `FINISH_QUEST_DATA`  | Optional convenience: just pops the screen.    |
///
/// Game-specific messages are routed via [onCustomBridgeMessage] (return
/// `true` to claim the message; `false` to fall through to the default
/// switch above).
class TwineQuestionnaireHost extends StatefulWidget {
  /// Stable identifier — also used as the default `surveyId` if a
  /// `SUBMIT_RESPONSE` message omits its own.
  final String surveyId;

  /// User-facing AppBar title.
  final String title;

  /// Asset path to the Twine HTML to load.
  final String htmlAsset;

  /// Default points awarded per `SUBMIT_RESPONSE` if the JS payload omits
  /// its own `pointsEarned`. Set to 0 for a "boring" control game.
  final int defaultPointsPerResponse;

  /// Optional handler invoked BEFORE the host's default switch on each
  /// inbound JS bridge message. Return `true` to claim the message;
  /// `false` to fall through.
  final Future<bool> Function(
          Map<String, dynamic> data, WebViewController webView)?
      onCustomBridgeMessage;

  final Color appBarColor;

  const TwineQuestionnaireHost({
    super.key,
    required this.surveyId,
    required this.title,
    required this.htmlAsset,
    this.defaultPointsPerResponse = 0,
    this.onCustomBridgeMessage,
    this.appBarColor = const Color(0xFF4A1D6C),
  });

  @override
  State<TwineQuestionnaireHost> createState() => _TwineQuestionnaireHostState();
}

class _TwineQuestionnaireHostState extends State<TwineQuestionnaireHost> {
  late final WebViewController _controller;

  // Latest BP logged in THIS host instance (via the LOG_BP bridge case).
  // On GO_HOME we pop with these values so a parent route — if any —
  // can inject them into its own SugarCube state without relying on
  // shared WebView localStorage.
  int? _lastLoggedSys;
  int? _lastLoggedDia;

  // One-shot guard so the snapshot + session-summary writes fire exactly
  // once per host instance regardless of which exit path the player took
  // (in-game GO_HOME button vs. AppBar back arrow vs. Android back gesture).
  bool _exited = false;

  // Tracks whether any SUBMIT_RESPONSE this session credited points.
  // Used by _performExit to decide whether to bump `surveysCompleted`
  // at exit time when no individual submit has done so already (the
  // Vascular Village per-quest pattern).
  bool _anyPointsEarned = false;

  // True once a SUBMIT_RESPONSE has bumped `surveysCompleted` (default
  // behavior). Lets us bump exactly once per session even when a game's
  // submits all use `countAsCompletion: false` — _performExit covers
  // those cases via the deferred bump.
  bool _completionAlreadyBumped = false;

  // Per-play session id stamped onto every write that comes out of this
  // host instance (telemetry, BP reading, HealthKit snapshot, survey
  // response). Lets researchers do a single Firestore query to
  // reconstruct one play of one game, instead of joining on time
  // ranges. Format: `${surveyId}_${millis}` — same convention as
  // MovementHooks.generateSessionId.
  late final String _sessionId;
  late final DateTime _startedAt;

  String get _phone =>
      Provider.of<UserDataProvider>(context, listen: false).phone;
  String get _uid =>
      Provider.of<UserDataProvider>(context, listen: false).uid;

  @override
  void initState() {
    super.initState();
    _sessionId =
        '${widget.surveyId}_${DateTime.now().millisecondsSinceEpoch}';
    _startedAt = DateTime.now();
    SessionManager.startGame(widget.title);
    TelemetryHooks.logEvent(
      '${widget.surveyId}_opened',
      parameters: {
        'gameId': widget.surveyId,
        'sessionId': _sessionId,
      },
      phone: _phone,
      userId: _uid,
    );
    _initWebView();
  }

  void _initWebView() {
    // Tag the user agent with the current participant id so the
    // inlined bridge JS can detect a participant switch on shared
    // devices and wipe stale per-user localStorage (BP history,
    // voyage gate, etc.) before SugarCube StoryInit reads it.
    // Without this, participant 124 logging in on a phone where
    // participant 123 just played sees 123's last BP reading on
    // their first launch of Vascular Village. "anon" is the
    // fallback when a Twine game opens before login completes.
    final pid = _uid.isEmpty ? 'anon' : _uid;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('CCQApp/$pid')
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            debugPrint('❌ ${widget.surveyId} WebView Error: '
                '${error.description}');
            // Report to Firestore so a failed game load isn't invisible
            // to researchers. errorType + description lets us
            // distinguish 404s from JS crashes from CORS-style failures.
            TelemetryHooks.logEvent(
              'webview_error',
              parameters: {
                'gameId': widget.surveyId,
                'sessionId': _sessionId,
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
                  await widget.onCustomBridgeMessage!(data, _controller);
              if (handled) return;
            }

            await _handleStandardMessage(data);
          } catch (e) {
            debugPrint('TwineQuestionnaireHost bridge error: $e');
          }
        },
      )
      ..loadFlutterAsset(widget.htmlAsset);
  }

  Future<void> _handleStandardMessage(Map<String, dynamic> data) async {
    switch (data['type']) {
      case 'GO_HOME':
      case 'FINISH_QUEST_DATA':
        await _performExit(exitReason: data['type'] as String);
        break;

      case 'LOG_BP':
        // Sent by the Quiet Minute game's Save passage after the user
        // enters their reading. The game already validates the input
        // (60-250 sys, 30-160 dia) before firing this. We trust that
        // validation and write straight through DailyLogHooks.logBP,
        // which awards points + bumps lifetime counters + writes the
        // immutable event row.
        final sys = data['systolic'];
        final dia = data['diastolic'];
        final mood = data['mood'];
        if (sys is num && dia is num && _uid.isNotEmpty) {
          await DailyLogHooks.logBP(
            uid: _uid,
            systolic: sys.toInt(),
            diastolic: dia.toInt(),
            mood: mood is num ? mood.toInt() : 2,
            sessionId: _sessionId,
            gameId: widget.surveyId,
          );
          // Track for the route-pop result so a parent route can pick up
          // the fresh reading.
          _lastLoggedSys = sys.toInt();
          _lastLoggedDia = dia.toInt();
          if (mounted) {
            PointsHooks.applyIncrements(context, const {
              'points': 50,
              'totalSessions': 1,
              'measurementsTaken': 1,
            });
            PointsHooks.applySets(context, {
              'lastSystolic': sys.toInt(),
              'lastDiastolic': dia.toInt(),
              'lastBPLogDate':
                  DateTime.now().toIso8601String().split('T')[0],
            });
          }
        }
        break;

      case 'LAUNCH_GAME':
        // A game is asking us to run another catalog game as a sub-flow,
        // returning here when it ends. Used by Vascular Village to route
        // the player through Quiet Minute for a calm-state BP reading
        // mid-story. We push a new TwineQuestionnaireHost on top with
        // the requested gameId; when it pops we inject any logged BP
        // into THIS host's WebView so the parent SugarCube state picks
        // up the fresh reading without relying on shared localStorage.
        final gameId = data['gameId'];
        if (gameId is String && gameId.isNotEmpty && mounted) {
          final result =
              await Navigator.of(context).push<Map<String, dynamic>?>(
            MaterialPageRoute(
              builder: (_) => TwineQuestionnaireHost(
                surveyId: gameId,
                title: gameId,
                htmlAsset: 'assets/game/$gameId.html',
                appBarColor: widget.appBarColor,
              ),
            ),
          );
          if (result != null && mounted) {
            final sys = result['systolic'];
            final dia = result['diastolic'];
            if (sys is int && dia is int) {
              // Inject the new BP into the parent game's SugarCube state
              // and re-render the current passage. Vascular Village's
              // Hub passage uses $lastSys / $lastDia at render time, so
              // this re-render is what makes the village reflect the
              // fresh reading without the player having to navigate.
              _controller.runJavaScript('''
                try {
                  if (window.SugarCube && SugarCube.State) {
                    SugarCube.State.variables.lastSys = $sys;
                    SugarCube.State.variables.lastDia = $dia;
                  }
                  if (window.Engine && typeof Engine.play === "function" &&
                      window.SugarCube && SugarCube.State &&
                      SugarCube.State.passage) {
                    Engine.play(SugarCube.State.passage);
                  }
                } catch (e) { /* swallow */ }
              ''');
            }
          }
        }
        break;

      case 'SAVE_STATE':
        final state = data['state'];
        if (state is String) {
          await MovementHooks.saveGameStateJson(
            uid: _uid,
            gameId: widget.surveyId,
            stateJson: state,
          );
        }
        break;

      case 'SUBMIT_RESPONSE':
        final answers = data['answers'];
        if (answers is Map) {
          final pointsEarned = (data['pointsEarned'] is num)
              ? (data['pointsEarned'] as num).toInt()
              : widget.defaultPointsPerResponse;
          // Default behavior: every points-earning submit also counts
          // as one completion. Games opt out with `countAsCompletion:
          // false` when their submits represent partial progress
          // (e.g. Vascular Village's per-quest credits). For those,
          // SurveyHooks skips the Firestore counter bump too, and
          // _performExit fires it once on exit instead.
          final countAsCompletion = data['countAsCompletion'] != false;

          // Stamp the response with this play's sessionId so the survey
          // doc can be tied back to the matching telemetry / health-
          // snapshot writes.
          final enrichedAnswers = Map<String, dynamic>.from(answers);
          enrichedAnswers['_sessionId'] = _sessionId;

          await SurveyHooks.submitResponse(
            uid: _uid,
            surveyId: (data['surveyId'] as String?) ?? widget.surveyId,
            answers: enrichedAnswers,
            pointsEarned: pointsEarned,
            countAsCompletion: countAsCompletion,
          );

          if (mounted && pointsEarned > 0) {
            _anyPointsEarned = true;
            final increments = <String, int>{'points': pointsEarned};
            if (countAsCompletion) {
              increments['surveysCompleted'] = 1;
              _completionAlreadyBumped = true;
            }
            PointsHooks.applyIncrements(context, increments);
          }

          TelemetryHooks.logEvent(
            '${widget.surveyId}_response_submitted',
            parameters: {
              'questionCount': answers.length,
              'pointsEarned': pointsEarned,
              'gameId': widget.surveyId,
              'sessionId': _sessionId,
            },
            phone: _phone,
            userId: _uid,
          );
        }
        break;

      case 'LOG_QUEST_COMPLETION':
        // Game-side equivalent of SUBMIT_RESPONSE for hub-and-spoke
        // games (Vascular Village). Routes through GameLogHooks so the
        // record lands in `userData/{uid}/gameLogs/{auto}` instead of
        // `surveys/...` — keeps the surveys collection reserved for
        // actual questionnaires. Otherwise mirrors the SUBMIT_RESPONSE
        // shape: same points-credit + countAsCompletion semantics, same
        // session-stamped enrichment, same deferred completion bump
        // path in _performExit when callers opt out.
        final questId = data['questId'];
        if (questId is String && questId.isNotEmpty) {
          final pointsEarned = (data['pointsEarned'] is num)
              ? (data['pointsEarned'] as num).toInt()
              : 0;
          final countAsCompletion = data['countAsCompletion'] != false;
          final gameId =
              (data['gameId'] as String?) ?? widget.surveyId;
          final questData = data['data'] is Map
              ? Map<String, dynamic>.from(data['data'] as Map)
              : null;

          await GameLogHooks.logQuestCompletion(
            uid: _uid,
            gameId: gameId,
            questId: questId,
            pointsEarned: pointsEarned,
            sessionId: _sessionId,
            data: questData,
            countAsCompletion: countAsCompletion,
          );

          if (mounted && pointsEarned > 0) {
            _anyPointsEarned = true;
            final increments = <String, int>{'points': pointsEarned};
            if (countAsCompletion) {
              increments['surveysCompleted'] = 1;
              _completionAlreadyBumped = true;
            }
            PointsHooks.applyIncrements(context, increments);
          }

          TelemetryHooks.logEvent(
            '${gameId}_quest_completed',
            parameters: {
              'questId': questId,
              'pointsEarned': pointsEarned,
              'gameId': gameId,
              'sessionId': _sessionId,
            },
            phone: _phone,
            userId: _uid,
          );
        }
        break;

      case 'TELEMETRY':
        final name = data['name'];
        if (name is String && name.isNotEmpty) {
          // Enrich every JS-fired event with the gameId + sessionId so
          // researchers can group events by game and join one specific
          // play together. userId lets them join cross-collection back
          // to user data.
          final params = data['params'] is Map
              ? Map<String, dynamic>.from(data['params'] as Map)
              : <String, dynamic>{};
          params['gameId'] = widget.surveyId;
          params['sessionId'] = _sessionId;
          TelemetryHooks.logEvent(
            name,
            parameters: params,
            phone: _phone,
            userId: _uid,
          );
        }
        break;

      default:
        // Unknown message type — silently ignored to keep the bridge
        // forward-compatible with future Twine pages.
        break;
    }
  }

  /// Single exit path used by every way out of the game: GO_HOME bridge
  /// message, AppBar back arrow, Android system back. Fires the
  /// HealthKit snapshot + game-end summary writes exactly once
  /// (`_exited` guard), then pops with any logged BP as the route result.
  Future<void> _performExit({required String exitReason}) async {
    if (_exited) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _exited = true;

    if (mounted) {
      // Deferred completion bump: if any submit this session credited
      // points AND none of them counted as a completion (all used
      // `countAsCompletion: false`), bump `surveysCompleted` once
      // now — both in local state for instant UI feedback and in
      // Firestore via OfflineQueue so the canonical record stays in
      // sync. SurveyHooks skipped the Firestore bump for those
      // partial submits, so the host owns this once-per-session
      // bump. Vascular Village's per-quest credits go through this
      // path; whole-game submits (Daily Check-In, Bingo Bash, etc.)
      // bump per submit and skip this branch entirely.
      if (_anyPointsEarned && !_completionAlreadyBumped) {
        PointsHooks.applyIncrements(
            context, const <String, int>{'surveysCompleted': 1});
        if (_uid.isNotEmpty) {
          unawaited(GetIt.instance<OfflineQueue>().enqueue(PendingOp.update(
            '${FirestorePaths.userData}/$_uid',
            {
              'surveysCompleted': OfflineFieldValue.increment(1),
              'lastSurveyId': widget.surveyId,
              'lastSurveyAt': OfflineFieldValue.nowTimestamp(),
            },
          )));
        }
      }
      // Fire-and-forget HealthKit snapshot stamped with this play's
      // sessionId so researchers can join the snapshot to the rest of
      // the per-session writes (passage_entered events, BP reading,
      // summary doc).
      unawaited(HealthHooks.logSnapshot(
        uid: _uid,
        gameId: widget.surveyId,
        sessionId: _sessionId,
      ));
      // Game-end summary doc — netguage CheckData-equivalent.
      unawaited(_writeSessionSummary(exitReason: exitReason));
    }

    // Pop with BP if any was logged. Parent routes (e.g. Vascular Village
    // launching Quiet Minute via CCQ.launchGame) read the result; routes
    // popped to dashboard ignore it.
    //
    // Important: explicitly type the map as `Map<String, dynamic>` —
    // a bare literal infers as `Map<String, int?>`, which is NOT a
    // subtype of `Map<String, dynamic>` because Dart's Map is invariant
    // in its value type. Without the explicit type, the awaiting
    // `push<Map<String, dynamic>?>` cast in the parent's LAUNCH_GAME
    // handler fails, the result lands as null, and Vascular Village's
    // SugarCube state never receives the freshly-logged BP — the Hub
    // re-renders with `--/--` until the next StoryInit picks it up
    // from localStorage.
    if (mounted) {
      final bpResult = (_lastLoggedSys != null && _lastLoggedDia != null)
          ? <String, dynamic>{
              'systolic': _lastLoggedSys,
              'diastolic': _lastLoggedDia,
            }
          : null;
      Navigator.of(context).pop(bpResult);
    }
  }

  /// Write a netguage-CheckData-style game-end summary doc. One row per
  /// play of one game by one user. Joins to telemetry events and any
  /// per-session writes (BP reading, HealthKit snapshot) by `sessionId`.
  Future<void> _writeSessionSummary({required String exitReason}) async {
    if (_uid.isEmpty) return;
    final endedAt = DateTime.now();
    final durationMs = endedAt.difference(_startedAt).inMilliseconds;
    try {
      await GetIt.instance<OfflineQueue>().enqueue(PendingOp.set(
        '${FirestorePaths.userData}/$_uid/gameSessions/$_sessionId',
        {
          'sessionId': _sessionId,
          'userId': _uid,
          'gameId': widget.surveyId,
          'hostType': 'TwineQuestionnaireHost',
          'startedAt': OfflineFieldValue.timestampFrom(_startedAt),
          'endedAt': OfflineFieldValue.timestampFrom(endedAt),
          'durationMs': durationMs,
          'exitReason': exitReason,
          'bpLogged': _lastLoggedSys != null && _lastLoggedDia != null,
          if (_lastLoggedSys != null) 'lastSystolic': _lastLoggedSys,
          if (_lastLoggedDia != null) 'lastDiastolic': _lastLoggedDia,
        },
      ));
    } catch (e) {
      debugPrint(
          'TwineQuestionnaireHost session summary write failed: $e');
    }
  }

  @override
  void dispose() {
    SessionManager.endGame();
    TelemetryHooks.logEvent(
      '${widget.surveyId}_closed',
      parameters: {
        'gameId': widget.surveyId,
        'sessionId': _sessionId,
      },
      phone: _phone,
      userId: _uid,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No Flutter AppBar — the Twine HTMLs render their own header inside
    // the WebView (`<div class="header">`), and the burger menu auto-
    // injected by `ccq_bridge.js` provides "Go to dashboard". Stacking
    // the native AppBar on top produced a redundant double-header:
    // back-arrow row + in-game header row eating ~110px of viewport
    // before the actual game content started. Removing the AppBar
    // gives the game the full screen height.
    //
    // Exit paths still covered:
    //   • Burger menu → "Go to dashboard" (bridge → GO_HOME → _performExit)
    //   • Android system back gesture (PopScope below → _performExit)
    //   • In-game completion buttons (e.g. Quiet Minute Done → CCQ.goHome)
    //
    // PopScope intercepts the back gesture so it goes through
    // _performExit (snapshot + summary writes) instead of popping
    // silently and skipping the data-collection writes.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _performExit(exitReason: 'back_button');
      },
      child: Scaffold(
        // Dark navy paints behind any inset region Android may reserve
        // for the system status bar — keeps the visual continuous if
        // the OS does carve out a sliver. Most Android builds put
        // status bar ABOVE the activity's content area (opaque),
        // meaning content already starts below the bar with no inset
        // needed. Earlier we wrapped the WebView in SafeArea(top:true)
        // which added EXTRA padding on top of that — visually a
        // stranded band of Scaffold bg color between the OS status
        // bar and the game's own header. Dropping SafeArea lets the
        // WebView fill all the way up, so the game header sits
        // directly under the status bar with no seam.
        backgroundColor: const Color(0xFF1a1b2e),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
