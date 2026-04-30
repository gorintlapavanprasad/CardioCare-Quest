import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
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

  String get _phone =>
      Provider.of<UserDataProvider>(context, listen: false).phone;
  String get _uid =>
      Provider.of<UserDataProvider>(context, listen: false).uid;

  @override
  void initState() {
    super.initState();
    SessionManager.startGame(widget.title);
    TelemetryHooks.logEvent('${widget.surveyId}_opened', phone: _phone);
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
        if (mounted) Navigator.of(context).pop();
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

          await SurveyHooks.submitResponse(
            uid: _uid,
            surveyId: (data['surveyId'] as String?) ?? widget.surveyId,
            answers: Map<String, dynamic>.from(answers),
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
            },
            phone: _phone,
          );
        }
        break;

      case 'TELEMETRY':
        final name = data['name'];
        if (name is String && name.isNotEmpty) {
          TelemetryHooks.logEvent(
            name,
            parameters: data['params'] is Map
                ? Map<String, dynamic>.from(data['params'] as Map)
                : null,
            phone: _phone,
          );
        }
        break;

      default:
        // Unknown message type — silently ignored to keep the bridge
        // forward-compatible with future Twine pages.
        break;
    }
  }

  @override
  void dispose() {
    SessionManager.endGame();
    TelemetryHooks.logEvent('${widget.surveyId}_closed', phone: _phone);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: widget.appBarColor,
        foregroundColor: Colors.white,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
