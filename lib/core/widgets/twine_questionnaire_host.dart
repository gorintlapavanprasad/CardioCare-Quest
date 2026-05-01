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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
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
          );

          if (mounted && pointsEarned > 0) {
            PointsHooks.applyIncrements(context, {
              'points': pointsEarned,
              'surveysCompleted': 1,
            });
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
    if (mounted) {
      final bpResult =
          (_lastLoggedSys != null && _lastLoggedDia != null)
              ? {
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
    // No AppBar title — the Twine HTMLs render their own visible heading
    // inside the WebView. Putting a duplicate title on the dark AppBar
    // also runs into a contrast bug (theme titleTextStyle is dark navy,
    // which disappears on dark purple). Back arrow + in-HTML title is
    // enough context.
    //
    // PopScope intercepts the Android system back gesture so it goes
    // through _performExit (snapshot + summary writes) instead of
    // popping silently and skipping the data-collection writes. The
    // AppBar back arrow is wired the same way.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _performExit(exitReason: 'back_button');
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: widget.appBarColor,
          foregroundColor: Colors.white,
          // Explicit iconTheme so the back arrow stays white on the dark
          // purple bar — without this, the global appBarTheme.iconTheme
          // (dark navy) overrides foregroundColor and the arrow becomes
          // invisible on dark purple.
          iconTheme: const IconThemeData(color: Colors.white),
          // Explicit leading so the icon style matches TwineGameHost's
          // back arrow across all games (Icons.arrow_back, not the
          // platform-adaptive default). Routes through _performExit so
          // every exit path fires the snapshot + summary writes.
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => _performExit(exitReason: 'back_arrow'),
          ),
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
