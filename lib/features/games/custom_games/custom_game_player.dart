// CustomGamePlayer - plays a game the user built themselves.
//
// It just looks at the game type and hands off to the right player:
//   • walk → CustomWalkGame (a GPS walk, like Dog Quest)
//   • quiz → _QuizPlayer below (answer questions, like the other quizzes)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/hooks/hooks.dart';
import '../../../core/providers/user_data_manager.dart';
import '../../../core/services/offline_queue.dart';
import '../../../core/theme/app_colors.dart';
import 'custom_game.dart';
import 'custom_games_repository.dart';
import 'custom_walk_game.dart';

// ---- THE ROUTER ----

// Picks the walk player or the quiz player based on the game's type.
class CustomGamePlayer extends StatelessWidget {
  final CustomGame game;
  const CustomGamePlayer({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    switch (game.gameType) {
      case CustomGameType.walk:
        return CustomWalkGame(game: game);
      case CustomGameType.quiz:
        return _QuizPlayer(game: game);
    }
  }
}

// ---- THE QUIZ PLAYER ----

// The three screens a quiz moves through, in order.
enum _Scene { welcome, question, result }

// The quiz player: welcome screen → questions → results screen.
class _QuizPlayer extends StatefulWidget {
  final CustomGame game;
  const _QuizPlayer({required this.game});

  @override
  State<_QuizPlayer> createState() => _CustomGamePlayerState();
}

class _CustomGamePlayerState extends State<_QuizPlayer> {
  _Scene _scene = _Scene.welcome; // which screen we're on
  // Copy the questions once when we start, so the list can't change
  // under us mid-play even if the cloud copy gets updated.
  late final List<QuizQuestion> _questions;
  int _currentQuestionIndex = 0; // which question is showing
  // The user's answers, in the same order as _questions. Filled in as
  // they tap; all sent together at the end.
  final List<String> _answers = [];
  late final String _sessionId; // ties all of this one play together
  late final DateTime _startedAt;
  bool _resultHooksFired = false; // so we only award points once

  // Runs once when the quiz opens: grab the questions, make an id for
  // this play, and note that the game was opened.
  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    // Get the questions to play (handles both new and old saved games).
    _questions = widget.game.effectiveQuestions;
    // A unique id for this one play. Every record we save below carries
    // it, so researchers can line them all up as one play later.
    _sessionId = '${_surveyId}_${_startedAt.millisecondsSinceEpoch}';

    // Note that the game was opened (for the researchers).
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

  // A name for this quiz's saved answers, e.g. "custom_ab12".
  String get _surveyId => 'custom_${widget.game.id}';

  // Runs when the user taps an answer. Saves it, then either shows the
  // next question or, on the last one, jumps to the results screen.
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
    // Only save + give points the first time we reach the results, so
    // going back to this screen can't hand out points twice.
    if (_resultHooksFired) return;
    _resultHooksFired = true;
    await _fireCompletionHooks();
  }

  // Runs once when the quiz is finished. Saves everything and hands out
  // points. Each numbered step below saves a different piece.
  Future<void> _fireCompletionHooks() async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    final game = widget.game;

    // 1. Mark this game as finished one more time (updates the card).
    if (uid.isNotEmpty) {
      // ignore: unawaited_futures
      CustomGamesRepository.instance.markCompleted(
        uid: uid,
        gameId: game.id,
      );
    }

    // 2. Save the actual answers and add the points. We save each
    //    question with its choices and the answer picked, so researchers
    //    can see exactly what was asked and answered.
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
        pointsEarned: game.pointsReward,
      );
    }

    // 3. Bump the points shown on screen right away, so the user sees
    //    their new total instantly instead of waiting for the save.
    if (mounted) {
      PointsHooks.applyIncrements(context, {
        'points': game.pointsReward,
        'totalSessions': 1,
      });
    }

    // 4. Note that the quiz was finished (for the researchers). Just
    //    counts and timing here, no answers, to keep it free of any
    //    personal info. The real answers were saved in step 2.
    // ignore: unawaited_futures
    TelemetryHooks.logEvent(
      'custom_game_session_completed',
      parameters: {
        'gameId': game.id,
        'sessionId': _sessionId,
        'category': game.category.name,
        'pointsReward': game.pointsReward,
        'questionCount': _questions.length,
        'answersCount': _answers.length,
        'durationMs':
            DateTime.now().difference(_startedAt).inMilliseconds,
      },
      userId: uid.isEmpty ? null : uid,
    );

    // 5. Grab a health snapshot from the watch/wearable at the end,
    //    tagged with this play's id so it lines up with the rest.
    if (uid.isNotEmpty) {
      // ignore: unawaited_futures
      HealthHooks.logSnapshot(
        uid: uid,
        gameId: _surveyId,
        sessionId: _sessionId,
      );
    }

    // 6. Save a short summary of this play. It's the same shape the
    //    other games save, so one search can pull up every play of
    //    every game together.
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
          // Which player made this record, so plays can be grouped by
          // type. We use the queue's time markers (below), because the
          // plain cloud ones don't survive being stored on the phone.
          'hostType': 'CustomGamePlayer.quiz',
          'startedAt': OfflineFieldValue.timestampFrom(_startedAt),
          'endedAt': OfflineFieldValue.nowTimestamp(),
          'durationMs':
              DateTime.now().difference(_startedAt).inMilliseconds,
          'pointsEarned': game.pointsReward,
          'exitReason': 'completed',
          'questionCount': _questions.length,
          'isCustomGame': true,
        },
        merge: true,
      ));
    }
  }

  // Shows whichever screen we're on right now: welcome, a question, or
  // the result.
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

// ---- SCREEN PARTS (looks only) ----

// The dark blue background all the quiz screens sit on.
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

// The top bar with the game's title.
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

// First screen: the game name, note, and a BEGIN button.
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

// Middle screen: one question with its answer buttons. Shows a
// "Question 2 of 3" counter when there's more than one.
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
                // Use a friendly default if the question text is blank.
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

// Last screen: "Great job", the points earned, and a DONE button.
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
                      Text(
                        '+${game.pointsReward}',
                        style: const TextStyle(
                          color: Color(0xFFfde725),
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
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

// The big white button (BEGIN / DONE).
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

// One answer-choice button on a question screen.
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
