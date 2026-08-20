import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';
import 'package:cardio_care_quest/core/widgets/game_web_style.dart';
import 'package:cardio_care_quest/features/games/game_completion_signal.dart';

// TwineQuestionnaireHost - runs a non-walking Twine game (survey, questionnaire,
// educational page) in a WebView. Handles BP logging, survey answers, and the
// shared exit path. One host for all non-movement games.

// Most game ids match their HTML file name, so LAUNCH_GAME can build the path
// straight from the id. A few don't, so list those exceptions here.
const Map<String, String> _launchGameAssetOverrides = {
  'control_daily_checkin': 'assets/game/control_game.html',
};

// Turn a game id into its HTML asset path, using the overrides above when the
// file name doesn't match the id.
String _assetForGameId(String gameId) =>
    _launchGameAssetOverrides[gameId] ?? 'assets/game/$gameId.html';

// The widget you add to a screen. Holds settings for one game; real work is in the State.
class TwineQuestionnaireHost extends StatefulWidget {
  // Unique id (also the default surveyId for SUBMIT_RESPONSE messages).
  final String surveyId;

  // Title shown in the UI.
  final String title;

  // Path to the Twine HTML file in assets. Null when [htmlContent] is used.
  final String? htmlAsset;

  // Raw HTML to load instead of an asset (used for runtime-built story games).
  // Exactly one of [htmlAsset] / [htmlContent] must be provided.
  final String? htmlContent;

  // Optional handler for game-specific bridge messages. Return true to claim.
  final Future<bool> Function(
          Map<String, dynamic> data, WebViewController webView)?
      onCustomBridgeMessage;

  final Color appBarColor;

  // When true, exit pops with the BP result so a parent game (e.g. Vascular Village)
  // can pick it up. When false (the default), exit pops to the dashboard.
  final bool popResultOnly;

  const TwineQuestionnaireHost({
    super.key,
    required this.surveyId,
    required this.title,
    this.htmlAsset,
    this.htmlContent,
    this.onCustomBridgeMessage,
    this.appBarColor = const Color(0xFF4A1D6C),
    this.popResultOnly = false,
  }) : assert((htmlAsset == null) != (htmlContent == null),
            'Provide exactly one of htmlAsset or htmlContent.');

  @override
  State<TwineQuestionnaireHost> createState() => _TwineQuestionnaireHostState();
}

// Holds live state for one play: WebView, session ids, flags.
class _TwineQuestionnaireHostState extends State<TwineQuestionnaireHost> {
  // ---- STATE ----
  late final WebViewController _controller; // drives the WebView (the game page)

  // Last BP saved this visit. Passed back to a parent game on exit.
  int? _lastLoggedSys; // last blood-pressure top number saved this visit
  int? _lastLoggedDia; // last blood-pressure bottom number saved this visit

  // Ensures exit cleanup (vitals + summary) runs only once.
  bool _exited = false;

  // True while the HTML is loading. Shows a spinner.
  bool _loading = true;

  // Did the player log any activity this visit (exercise, meal, meds, a submit,
  // a quest)? Used to decide if we owe a completion tick at exit.
  bool _anyActivityLogged = false;

  // Prevents bumping the surveysCompleted count more than once per visit.
  bool _completionAlreadyBumped = false;

  // True once HealthKit vitals have been captured. Fires at the most meaningful
  // moment (BP save, or success screen). _performExit skips its snapshot if already set.
  bool _snapshotLogged = false;

  // Id for this play. Tagged on every write so one play can be joined in one query.
  late final String _sessionId;
  late final DateTime _startedAt; // when this play began, for the duration

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _phoneForDispose = _phone;
    _uidForDispose = _uid;
  }

  // Build the WebView, wire up the bridge, and load the game.
  void _initWebView() {
    // User-agent includes the participant id so the bridge JS can wipe stale
    // localStorage when a different participant opens the game on a shared device.
    final pid = _uid.isEmpty ? 'anon' : _uid;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('CCQApp/$pid')
      ..setBackgroundColor(Colors.white)
      ..setOnConsoleMessage((msg) {
        // Surfaces SugarCube boot errors and any in-game console output so a
        // blank WebView can be diagnosed from the Flutter logs.
        debugPrint('WEBVIEW[${widget.surveyId}] ${msg.level.name}: ${msg.message}');
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            await _controller.runJavaScript(kCcqGameStyleInjectionJs);
            await _injectBridge();
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            debugPrint('❌ ${widget.surveyId} WebView Error: '
                '${error.description}');
            // Drop the spinner so the player can tap Home.
            if ((error.isForMainFrame ?? false) && mounted) {
              setState(() => _loading = false);
            }
            // Log failures so researchers can see them.
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
      );

    // Story games built at runtime come in as raw HTML; everything else loads
    // from a bundled asset. The bridge is injected the same way for both.
    // The baseUrl gives the page a real web origin so the SugarCube engine's
    // localStorage-backed boot works (a null origin makes it throw and render
    // nothing).
    if (widget.htmlContent != null) {
      _controller.loadHtmlString(
        widget.htmlContent!,
        baseUrl: 'https://cardiocarequest.app/',
      );
    } else {
      _controller.loadFlutterAsset(widget.htmlAsset!);
    }
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
      debugPrint('${widget.surveyId} bridge inject failed: $e');
    }
  }

  // ---- JS BRIDGE MESSAGES ----
  Future<void> _handleStandardMessage(Map<String, dynamic> data) async {
    switch (data['type']) {
      // Player (or game) wants to exit.
      case 'GO_HOME':
      case 'FINISH_QUEST_DATA':
        await _performExit(exitReason: data['type'] as String);
        break;

      // Player saved a BP reading. The game already validates the numbers before sending.
      case 'LOG_BP':
        final sys = data['systolic'];
        final dia = data['diastolic'];
        final mood = data['mood'];
        if (sys is num && dia is num && _uid.isNotEmpty) {
          _anyActivityLogged = true;
          await DailyLogHooks.logBP(
            uid: _uid,
            systolic: sys.toInt(),
            diastolic: dia.toInt(),
            mood: mood is num ? mood.toInt() : 2,
            sessionId: _sessionId,
            gameId: widget.surveyId,
          );
          // Store for the exit pop result so a parent game can use the reading.
          _lastLoggedSys = sys.toInt();
          _lastLoggedDia = dia.toInt();
          // Grab vitals at the moment of the BP save, not later - that's the
          // research-meaningful reading.
          if (!_snapshotLogged) {
            _snapshotLogged = true; // once per visit
            unawaited(HealthHooks.logSnapshot(
              uid: _uid,
              gameId: widget.surveyId,
              sessionId: _sessionId,
            ));
          }
          if (mounted) {
            PointsHooks.applyIncrements(context, const {
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

      // Player confirmed some physical activity. Save an exercise log and mirror
      // the counters to the on-screen numbers.
      case 'LOG_EXERCISE':
        final activity = data['activity'];
        final minutes = data['minutes'];
        if (activity is String && activity.isNotEmpty && _uid.isNotEmpty) {
          await DailyLogHooks.logExercise(
            uid: _uid,
            activity: activity,
            minutes: minutes is num ? minutes.toInt() : 10,
          );
          if (mounted) {
            _anyActivityLogged = true;
            PointsHooks.applyIncrements(context, {
              'exercisesLogged': 1,
              if (minutes is num) 'totalExerciseMinutes': minutes.toInt(),
            });
          }
        }
        break;

      // Player confirmed a healthy meal. Save a meal log and mirror the counter.
      case 'LOG_MEAL':
        if (_uid.isNotEmpty) {
          final notes = data['notes'] is String ? data['notes'] as String : '';
          final rating = data['rating'] is num ? (data['rating'] as num).toInt() : 4;
          await DailyLogHooks.logMeal(
            uid: _uid,
            mealNotes: notes,
            mealRating: rating,
            hasMealPhoto: false,
          );
          if (mounted) {
            _anyActivityLogged = true;
            PointsHooks.applyIncrements(context, const {
              'mealsLogged': 1,
            });
          }
        }
        break;

      // Player checked in about their medicine. Save it (streak comes from the
      // provider) and mirror the new streak.
      case 'LOG_MEDICATION':
        if (_uid.isNotEmpty) {
          final taken = data['taken'] == true;
          final provider =
              Provider.of<UserDataProvider>(context, listen: false);
          final currentStreak =
              (provider.userData?['medicationStreak'] as num?)?.toInt() ?? 0;
          await DailyLogHooks.logMedication(
            uid: _uid,
            taken: taken,
            currentStreak: currentStreak,
          );
          if (mounted) {
            _anyActivityLogged = true;
            PointsHooks.applySets(
              context, {'medicationStreak': taken ? currentStreak + 1 : 0});
          }
        }
        break;

      // Whole-play score summary. Records the trivia_completed event.
      case 'LOG_TRIVIA':
        if (_uid.isNotEmpty) {
          final score = data['score'] is num ? (data['score'] as num).toInt() : 0;
          final total = data['total'] is num ? (data['total'] as num).toInt() : 0;
          await DailyLogHooks.logTrivia(
            uid: _uid,
            score: score,
            totalQuestions: total,
          );
        }
        break;

      // Game wants to open another game on top, then resume here when it finishes.
      // Used by Vascular Village to send the player through Quiet Minute for a calm BP read.
      case 'LAUNCH_GAME':
        final gameId = data['gameId'];
        if (gameId is String && gameId.isNotEmpty && mounted) {
          final result =
              await Navigator.of(context).push<Map<String, dynamic>?>(
            MaterialPageRoute(
              builder: (_) => TwineQuestionnaireHost(
                surveyId: gameId,
                title: gameId,
                htmlAsset: _assetForGameId(gameId),
                appBarColor: widget.appBarColor,
                // Sub-flow: pop straight back to THIS parent with the BP
                // reading rather than jumping to the dashboard.
                popResultOnly: true,
              ),
            ),
          );
          if (result != null && mounted) {
            final sys = result['systolic'];
            final dia = result['diastolic'];
            if (sys is int && dia is int) {
              // Wait 50ms for the WebView to settle after the route pop on Android,
              // otherwise the JS call fires into an off-screen render tree.
              await Future<void>.delayed(const Duration(milliseconds: 50));
              if (!mounted) break;
              final whenMs = DateTime.now().millisecondsSinceEpoch;
              // Inject the BP into SugarCube state and seed quietMinute_history in
              // localStorage. The seed is a fallback: Android webview_flutter doesn't
              // share localStorage across WebViewController instances, so the Hub's
              // self-heal script wouldn't find the reading otherwise.
              _controller.runJavaScript('''
                try {
                  /* Seed `quietMinute_history` so Hub's self-heal
                     script finds the reading on its very next render.
                     unshift to keep "latest first" - same shape Quiet
                     Landscape uses. _seededFrom is a debug breadcrumb
                     researchers can use to distinguish writes from
                     in-game saves vs. host injections in the per-
                     WebView storage. */
                  try {
                    var hist = [];
                    try {
                      var existing = window.localStorage.getItem(
                          "quietMinute_history");
                      if (existing) hist = JSON.parse(existing) || [];
                    } catch (e) {}
                    hist.unshift({
                      sys: $sys,
                      dia: $dia,
                      when: $whenMs,
                      _seededFrom: "host_launchgame_popback"
                    });
                    if (hist.length > 100) hist = hist.slice(0, 100);
                    window.localStorage.setItem(
                        "quietMinute_history",
                        JSON.stringify(hist));
                  } catch (e) {}

                  if (window.SugarCube && SugarCube.State) {
                    SugarCube.State.variables.lastSys = $sys;
                    SugarCube.State.variables.lastDia = $dia;
                  }
                  /* Use Engine.show() (in-place redisplay of the
                     current passage) rather than Engine.play() -
                     play() pushes a new history moment which on
                     Android webview_flutter sometimes lands AFTER
                     the resume-from-background visual settle and
                     the participant sees the stale render until
                     they navigate elsewhere and back. show() is
                     the documented "I changed variables, please
                     refresh the view" path and it repaints the
                     current moment immediately. Falls back to a
                     no-op if Engine isn't ready yet. */
                  if (window.Engine && typeof Engine.show === "function") {
                    Engine.show();
                  } else if (window.Engine &&
                             typeof Engine.play === "function" &&
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

      // Game asks whether the player has logged a BP today. We answer from
      // UserDataProvider (canonical Firestore values) and seed localStorage so
      // the Hub self-heal script doesn't have to ask again next render.
      case 'GET_TODAY_BP':
        if (mounted) {
          final provider =
              Provider.of<UserDataProvider>(context, listen: false);
          final userMap = provider.userData;
          final today =
              DateTime.now().toIso8601String().split('T')[0];
          // Only inject if the loaded data belongs to the current participant.
          // On a shared device this prevents one person's BP leaking to another.
          final loadedUid = userMap?['uid'] as String?;
          final liveUid = _uid;
          final uidMatches = loadedUid != null &&
              loadedUid.isNotEmpty &&
              liveUid.isNotEmpty &&
              loadedUid == liveUid;
          if (userMap != null &&
              uidMatches &&
              userMap['lastBPLogDate'] == today) {
            final sys = (userMap['lastSystolic'] as num?)?.toInt();
            final dia = (userMap['lastDiastolic'] as num?)?.toInt();
            if (sys != null && dia != null) {
              final whenMs = DateTime.now().millisecondsSinceEpoch;
              _controller.runJavaScript('''
                try {
                  /* Seed this WebView's localStorage so Hub's
                     self-heal script (and any future StoryInit in
                     the same launch) finds the reading without
                     another round-trip. unshift to keep "latest
                     first" - same shape Quiet Landscape uses. */
                  try {
                    var hist = [];
                    try {
                      var existing = window.localStorage.getItem(
                          "quietMinute_history");
                      if (existing) hist = JSON.parse(existing) || [];
                    } catch (e) {}
                    hist.unshift({
                      sys: $sys,
                      dia: $dia,
                      when: $whenMs,
                      _seededFrom: "host_firestore"
                    });
                    if (hist.length > 100) hist = hist.slice(0, 100);
                    window.localStorage.setItem(
                        "quietMinute_history",
                        JSON.stringify(hist));
                  } catch (e) {}
                  /* Inject into SugarCube state and re-render the
                     current passage so Welcome / Hub picks up the
                     fresh reading immediately. Engine.show() does
                     an in-place redisplay without pushing a new
                     history moment - see the LAUNCH_GAME case for
                     the why-not-Engine.play rationale. */
                  if (window.SugarCube && SugarCube.State) {
                    SugarCube.State.variables.lastSys = $sys;
                    SugarCube.State.variables.lastDia = $dia;
                  }
                  if (window.Engine && typeof Engine.show === "function") {
                    Engine.show();
                  } else if (window.Engine &&
                             typeof Engine.play === "function" &&
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

      // Save Twine game state for later resume.
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

      // Player submitted survey answers. Optionally count as one completion.
      case 'SUBMIT_RESPONSE':
        final answers = data['answers'];
        if (answers is Map) {
          // Mark done so the launcher can show the feedback popup.
          GameCompletionSignal.markCompleted(widget.surveyId);
          // countAsCompletion: false means partial progress (e.g. a Vascular Village
          // mini-quest). _performExit fires the completion bump once at exit instead.
          final countAsCompletion = data['countAsCompletion'] != false;

          // Tag answers with the session id for later joining.
          final enrichedAnswers = Map<String, dynamic>.from(answers);
          enrichedAnswers['_sessionId'] = _sessionId;

          // Who answered? The game can say; otherwise fall back to the login prompt choice.
          final respondent = (data['respondent'] as String?) ??
              (mounted
                  ? Provider.of<UserDataProvider>(context, listen: false)
                      .respondent
                  : null);

          await SurveyHooks.submitResponse(
            uid: _uid,
            surveyId: (data['surveyId'] as String?) ?? widget.surveyId,
            answers: enrichedAnswers,
            countAsCompletion: countAsCompletion,
            respondent: respondent,
          );

          if (mounted) {
            _anyActivityLogged = true;
            if (countAsCompletion) {
              _completionAlreadyBumped = true;
              PointsHooks.applyIncrements(
                  context, const <String, int>{'surveysCompleted': 1});
            }
          }

          // Capture vitals at the success screen for whole-game completions.
          // Per-quest submits use _performExit's catch-all instead.
          if (countAsCompletion && !_snapshotLogged) {
            _snapshotLogged = true;
            unawaited(HealthHooks.logSnapshot(
              uid: _uid,
              gameId: widget.surveyId,
              sessionId: _sessionId,
            ));
          }

          TelemetryHooks.logEvent(
            '${widget.surveyId}_response_submitted',
            parameters: {
              'questionCount': answers.length,
              'gameId': widget.surveyId,
              'sessionId': _sessionId,
            },
            phone: _phone,
            userId: _uid,
          );
        }
        break;

      // Hub-and-spoke games (e.g. Vascular Village) use this to record finishing a mini-quest.
      // Goes to gameLogs, not surveys, keeping the surveys collection clean.
      case 'LOG_QUEST_COMPLETION':
        final questId = data['questId'];
        if (questId is String && questId.isNotEmpty) {
          // Mark done so the launcher can show the feedback popup.
          GameCompletionSignal.markCompleted(
              (data['gameId'] as String?) ?? widget.surveyId);
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
            sessionId: _sessionId,
            data: questData,
            countAsCompletion: countAsCompletion,
          );

          if (mounted) {
            _anyActivityLogged = true;
            if (countAsCompletion) {
              _completionAlreadyBumped = true;
              PointsHooks.applyIncrements(
                  context, const <String, int>{'surveysCompleted': 1});
            }
          }

          // Only fire for whole-game completions. Per-quest ones use _performExit's catch-all.
          if (countAsCompletion && !_snapshotLogged) {
            _snapshotLogged = true;
            unawaited(HealthHooks.logSnapshot(
              uid: _uid,
              gameId: gameId,
              sessionId: _sessionId,
            ));
          }

          TelemetryHooks.logEvent(
            '${gameId}_quest_completed',
            parameters: {
              'questId': questId,
              'gameId': gameId,
              'sessionId': _sessionId,
            },
            phone: _phone,
            userId: _uid,
          );
        }
        break;

      // Game fires a custom analytics event. We add gameId + sessionId for joining.
      case 'TELEMETRY':
        final name = data['name'];
        if (name is String && name.isNotEmpty) {
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

      // Unknown message types are ignored so the bridge stays forward-compatible.
      default:
        break;
    }
  }

  // ---- EXIT & SUMMARY ----

  // The one exit path for all ways out (GO_HOME, back arrow, back gesture).
  // Runs wrap-up writes exactly once (_exited guard), then pops.
  Future<void> _performExit({required String exitReason}) async {
    if (_exited) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _exited = true;

    if (mounted) {
      // If the player logged activity but no submit was marked as a completion
      // (e.g. Vascular Village per-quest credits), bump surveysCompleted once now.
      if (_anyActivityLogged && !_completionAlreadyBumped) {
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
      // Catch-all vitals snapshot: fires if nothing earlier did (abandoned game,
      // or hub-and-spoke games that use countAsCompletion: false per submit).
      if (!_snapshotLogged) {
        _snapshotLogged = true;
        unawaited(HealthHooks.logSnapshot(
          uid: _uid,
          gameId: widget.surveyId,
          sessionId: _sessionId,
        ));
      }
      unawaited(_writeSessionSummary(exitReason: exitReason));
    }

    // Pop and pass any BP reading back. The map must be typed explicitly as
    // Map<String, dynamic> or Dart's invariant Map type causes the parent
    // LAUNCH_GAME cast to fail and Vascular Village never gets the reading.
    if (mounted) {
      final bpResult = (_lastLoggedSys != null && _lastLoggedDia != null)
          ? <String, dynamic>{
              'systolic': _lastLoggedSys,
              'diastolic': _lastLoggedDia,
            }
          : null;
      // Sub-flow games pop once; top-level games pop to the dashboard.
      if (widget.popResultOnly) {
        Navigator.of(context).pop(bpResult);
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  // Write a one-row session summary for researchers.
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
      phone: _phoneForDispose,
      userId: _uidForDispose,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No Flutter AppBar: the Twine HTML renders its own header. PopScope
    // intercepts the back gesture so _performExit always runs.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _performExit(exitReason: 'back_button');
      },
      child: Scaffold(
        // Dark navy fills behind the status bar. SafeArea was removed to avoid
        // a gap between the status bar and the game's own header.
        backgroundColor: const Color(0xFF1a1b2e),
        // Home button is always visible as a fallback if the game's own menu is missing.
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
          ],
        ),
      ),
    );
  }
}
