import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';

// Short "how was it?" popup shown after a game finishes. Four questions,
// each answered with five emoji faces. Answers go via SurveyHooks.
// Only games listed here get the popup.
const Map<String, List<Map<String, String>>> gameFeedbackQuestions = {
  'salt_sludge': [
    {'key': 'fun', 'text': 'Was it fun?'},
    {'key': 'easy', 'text': 'Was it easy?'},
    {'key': 'learn', 'text': 'Did it help you learn about salt?'},
    {'key': 'again', 'text': 'Play again?'},
  ],
  'dog_quest': [
    {'key': 'fun', 'text': 'Was it fun?'},
    {'key': 'easy', 'text': 'Was it easy?'},
    {'key': 'learn', 'text': 'Did it make you want to walk more?'},
    {'key': 'again', 'text': 'Play again?'},
  ],
  'dash_diet_game': [
    {'key': 'fun', 'text': 'Was it fun?'},
    {'key': 'easy', 'text': 'Was it easy?'},
    {'key': 'learn', 'text': 'Did it help you pick better foods?'},
    {'key': 'again', 'text': 'Play again?'},
  ],
  'vascular_village': [
    {'key': 'fun', 'text': 'Was it fun?'},
    {'key': 'easy', 'text': 'Was it easy?'},
    {'key': 'learn', 'text': 'Did it help you learn about blood vessels?'},
    {'key': 'again', 'text': 'Play again?'},
  ],
  'bingo_bash': [
    {'key': 'fun', 'text': 'Was it fun?'},
    {'key': 'easy', 'text': 'Was it easy?'},
    {'key': 'learn', 'text': 'Did you learn something new?'},
    {'key': 'again', 'text': 'Play again?'},
  ],
};

// Loads the feedback HTML, passes the game's questions, saves answers, closes.
class GameFeedbackScreen extends StatefulWidget {
  final String gameId;
  final String gameTitle;

  const GameFeedbackScreen({
    super.key,
    required this.gameId,
    required this.gameTitle,
  });

  @override
  State<GameFeedbackScreen> createState() => _GameFeedbackScreenState();
}

class _GameFeedbackScreenState extends State<GameFeedbackScreen> {
  late final WebViewController _controller;
  bool _handled = false; // save/close runs once, no matter how we leave

  String get _uid =>
      Provider.of<UserDataProvider>(context, listen: false).uid;

  @override
  void initState() {
    super.initState();
    final questions = gameFeedbackQuestions[widget.gameId] ?? const [];
    final config = jsonEncode({
      'title': widget.gameTitle,
      'questions': questions,
    });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _controller.runJavaScript(
              'window.__ccqFeedback = $config;'
              'if (window.__renderFeedback) { window.__renderFeedback(); }',
            );
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (message) async {
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            switch (data['type']) {
              case 'SUBMIT':
                await _save(data['answers']);
                break;
              case 'CLOSE':
                _close();
                break;
            }
          } catch (e) {
            debugPrint('GameFeedback bridge error: $e');
          }
        },
      )
      ..loadFlutterAsset('assets/game/game_feedback.html');
  }

  // Saves the answers, pauses briefly for the thank-you message, then closes.
  Future<void> _save(dynamic answers) async {
    if (_handled) return;
    _handled = true;

    if (answers is Map && _uid.isNotEmpty) {
      final enriched = <String, dynamic>{'gameId': widget.gameId};
      answers.forEach((key, value) => enriched['$key'] = value);
      await SurveyHooks.submitResponse(
        uid: _uid,
        surveyId: 'game_feedback',
        answers: enriched,
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 900));
    _close();
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1b2e),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}
