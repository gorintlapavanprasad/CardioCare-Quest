// Routes to CustomWalkGame (walk) or _QuizPlayer (quiz) based on game type.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/hooks/hooks.dart';
import '../../../core/providers/user_data_manager.dart';
import '../../../core/services/offline_queue.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/twine_questionnaire_host.dart';
import 'custom_game.dart';
import 'custom_games_repository.dart';
import 'custom_twine_builder.dart';
import 'custom_walk_game.dart';

class CustomGamePlayer extends StatelessWidget {
  final CustomGame game;
  const CustomGamePlayer({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    switch (game.gameType) {
      case CustomGameType.story:
        return _StoryPlayer(game: game);
      case CustomGameType.walk:
        return CustomWalkGame(game: game);
      case CustomGameType.quiz:
        return _QuizPlayer(game: game);
    }
  }
}

// Plays a story game: generates the Twine HTML from the scenes and runs it in
// the shared WebView host, which injects the CCQ bridge so the story reaches the
// full hooks API. The host fires SurveyHooks/health/telemetry for us; we
// only bump the dashboard completion counter when the story submits.
class _StoryPlayer extends StatefulWidget {
  final CustomGame game;
  const _StoryPlayer({required this.game});

  @override
  State<_StoryPlayer> createState() => _StoryPlayerState();
}

class _StoryPlayerState extends State<_StoryPlayer> {
  late final Future<String> _htmlFuture;
  bool _completionMarked = false; // so we bump the counter only once per play

  @override
  void initState() {
    super.initState();
    _htmlFuture = _buildHtml();
  }

  Future<String> _buildHtml() async {
    final template =
        await rootBundle.loadString('assets/game/custom_game_template.html');
    return buildStoryHtml(widget.game, template: template);
  }

  // Watches the bridge for the story's submit, then increments completedCount.
  // Returns false so the host still runs its standard survey/health work.
  Future<bool> _onBridgeMessage(
      Map<String, dynamic> data, WebViewController controller) async {
    if (data['type'] == 'SUBMIT_RESPONSE' && !_completionMarked) {
      _completionMarked = true;
      final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
      if (uid.isNotEmpty) {
        // ignore: unawaited_futures
        CustomGamesRepository.instance.markCompleted(
          uid: uid,
          gameId: widget.game.id,
        );
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _htmlFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFF1a1b2e),
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }
        return TwineQuestionnaireHost(
          surveyId: 'custom_${widget.game.id}',
          title: widget.game.title,
          htmlContent: snapshot.data!,
          onCustomBridgeMessage: _onBridgeMessage,
        );
      },
    );
  }
}

// The three screens in a quiz.
enum _Scene { welcome, question, result }

// Quiz player: welcome → questions → results.
class _QuizPlayer extends StatefulWidget {
  final CustomGame game;
  const _QuizPlayer({required this.game});

  @override
  State<_QuizPlayer> createState() => _CustomGamePlayerState();
}

class _CustomGamePlayerState extends State<_QuizPlayer> {
  _Scene _scene = _Scene.welcome; // which screen we're on
  // Snapshot taken at start so a cloud update can't change questions mid-play.
  late final List<QuizQuestion> _questions;
  int _currentQuestionIndex = 0; // which question is showing
  // Answers collected in order, sent together when done.
  final List<String> _answers = [];
  late final String _sessionId; // ties all of this one play together
  late final DateTime _startedAt;
  bool _resultHooksFired = false; // so we only fire result hooks once

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _questions = widget.game.effectiveQuestions;
    // ID ties all saved records from this one play together.
    _sessionId = '${_surveyId}_${_startedAt.millisecondsSinceEpoch}';

    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    // ignore: unawaited_futures
    TelemetryHooks.logEvent(
      'custom_game_opened',
      parameters: {
        'gameId': widget.game.id,
        'sessionId': _sessionId,
        'category': widget.game.category.name,
      },
      userId: uid.isEmpty ? null : uid,
    );
  }

  String get _surveyId => 'custom_${widget.game.id}';

  // Records the answer and moves to the next question or results.
  Future<void> _onAnswerTapped(String answer) async {
    final isLast = _currentQuestionIndex >= _questions.length - 1;
    setState(() {
      _answers.add(answer);
      if (isLast) {
        _scene = _Scene.result;
      } else {
        _currentQuestionIndex++;
      }
    });
    if (!isLast) return;
    // Guard prevents double-awarding if the screen is somehow reached twice.
    if (_resultHooksFired) return;
    _resultHooksFired = true;
    await _fireCompletionHooks();
  }

  // Called once when the quiz finishes. Saves results.
  Future<void> _fireCompletionHooks() async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    final game = widget.game;

    // 1. Increment the game's completion count (updates the dashboard card).
    if (uid.isNotEmpty) {
      // ignore: unawaited_futures
      CustomGamesRepository.instance.markCompleted(
        uid: uid,
        gameId: game.id,
      );
    }

    // 2. Save answers with each question's choices for research.
    if (uid.isNotEmpty) {
      // ignore: unawaited_futures
      SurveyHooks.submitResponse(
        uid: uid,
        surveyId: _surveyId,
        answers: {
          'questions': List.generate(_questions.length, (i) {
            final q = _questions[i];
            return <String, dynamic>{
              'prompt': q.prompt,
              'options': q.options,
              'answer': i < _answers.length ? _answers[i] : null,
            };
          }),
          'questionCount': _questions.length,
        },
      );
    }

    // 3. Update session totals on screen immediately.
    if (mounted) {
      PointsHooks.applyIncrements(context, {
        'totalSessions': 1,
      });
    }

    // 4. Log completion event for research (counts/timing only, no answers).
    // ignore: unawaited_futures
    TelemetryHooks.logEvent(
      'custom_game_session_completed',
      parameters: {
        'gameId': game.id,
        'sessionId': _sessionId,
        'category': game.category.name,
        'questionCount': _questions.length,
        'answersCount': _answers.length,
        'durationMs':
            DateTime.now().difference(_startedAt).inMilliseconds,
      },
      userId: uid.isEmpty ? null : uid,
    );

    // 5. Capture a health snapshot at the end of the session.
    if (uid.isNotEmpty) {
      // ignore: unawaited_futures
      HealthHooks.logSnapshot(
        uid: uid,
        gameId: _surveyId,
        sessionId: _sessionId,
      );
    }

    // 6. Save a session summary in the same shape as other games.
    if (uid.isNotEmpty) {
      // ignore: unawaited_futures
      GetIt.instance<OfflineQueue>().enqueue(PendingOp.set(
        '${FirestorePaths.userData}/$uid/gameSessions/$_sessionId',
        {
          'sessionId': _sessionId,
          'userId': uid,
          'gameId': _surveyId,
          'gameTitle': game.title,
          'category': game.category.name,
          // Use queue time markers here - plain cloud timestamps can't
          // survive being stored offline on the phone.
          'hostType': 'CustomGamePlayer.quiz',
          'startedAt': OfflineFieldValue.timestampFrom(_startedAt),
          'endedAt': OfflineFieldValue.nowTimestamp(),
          'durationMs':
              DateTime.now().difference(_startedAt).inMilliseconds,
          'exitReason': 'completed',
          'questionCount': _questions.length,
          'isCustomGame': true,
        },
        merge: true,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF1a1b2e),
        body: SafeArea(
          bottom: false,
          child: _PhoneFrame(
            categoryColor: AppColors.primary,
            child: switch (_scene) {
              _Scene.welcome => _WelcomeScene(
                  game: widget.game,
                  onStart: () => setState(() => _scene = _Scene.question),
                ),
              _Scene.question => _QuestionScene(
                  game: widget.game,
                  question: _questions[_currentQuestionIndex],
                  questionIndex: _currentQuestionIndex,
                  questionTotal: _questions.length,
                  onAnswer: _onAnswerTapped,
                ),
              _Scene.result => _ResultScene(
                  game: widget.game,
                  questionTotal: _questions.length,
                  onDone: () => Navigator.of(context).pop(),
                ),
            },
          ),
        ),
      ),
    );
  }
}

// Dark blue background for all quiz screens.
class _PhoneFrame extends StatelessWidget {
  final Color categoryColor;
  final Widget child;

  const _PhoneFrame({required this.categoryColor, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1a3a5c), Color(0xFF2a5074), Color(0xFF3a6a94)],
        ),
      ),
      child: child,
    );
  }
}

// Top bar with the game's title.
class _GameHeader extends StatelessWidget {
  final String title;
  const _GameHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// Welcome screen: game name, description, and BEGIN button.
class _WelcomeScene extends StatelessWidget {
  final CustomGame game;
  final VoidCallback onStart;
  const _WelcomeScene({required this.game, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GameHeader(title: game.title),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: [
                Icon(game.iconData, color: Colors.white, size: 64),
                const SizedBox(height: 18),
                Text(
                  game.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (game.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    game.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ],
                const Spacer(),
                _PrimaryButton(label: 'BEGIN', onPressed: onStart),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Question screen with answer buttons. Shows a counter for multi-question quizzes.
class _QuestionScene extends StatelessWidget {
  final CustomGame game;
  final QuizQuestion question;
  final int questionIndex;
  final int questionTotal;
  final ValueChanged<String> onAnswer;
  const _QuestionScene({
    required this.game,
    required this.question,
    required this.questionIndex,
    required this.questionTotal,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final showCounter = questionTotal > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GameHeader(title: game.title),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: [
                if (showCounter) ...[
                  Text(
                    'Question ${questionIndex + 1} of $questionTotal',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else
                  const SizedBox(height: 12),
                // Fallback if the question text was left blank.
                Text(
                  question.prompt.isEmpty
                      ? 'How did it go?'
                      : question.prompt,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 32),
                ...question.options.map((opt) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _OptionButton(
                        label: opt,
                        onPressed: () => onAnswer(opt),
                      ),
                    )),
                const Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Results screen: a completion message and a DONE button.
class _ResultScene extends StatelessWidget {
  final CustomGame game;
  final int questionTotal;
  final VoidCallback onDone;
  const _ResultScene({
    required this.game,
    required this.questionTotal,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = questionTotal > 1
        ? 'You answered all $questionTotal questions.'
        : 'Thanks for checking in.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GameHeader(title: game.title),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Color(0xFFfde725),
                        size: 56,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Great job',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        subtitle,
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
            ),
          ),
        ),
      ],
    );
  }
}

// Large white button (BEGIN / DONE).
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

// Answer-choice button.
class _OptionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _OptionButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
