// CustomGamePlayer — router for participant-authored games.
//
// Different game TYPES use different player implementations, each
// firing the appropriate hooks chain for that gameplay style:
//
//   • walk → CustomWalkGame (LocationDispatcher + MovementHooks
//            pushPing/endSession + HealthHooks, like Dog Quest)
//   • quiz → _QuizPlayer below (SurveyHooks.submitResponse +
//            PointsHooks + HealthHooks, like the Twine questionnaires)
//
// New types can be added by extending CustomGameType and adding a
// case here.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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

enum _Scene { welcome, question, result }

class _QuizPlayer extends StatefulWidget {
  final CustomGame game;
  const _QuizPlayer({required this.game});

  @override
  State<_QuizPlayer> createState() => _CustomGamePlayerState();
}

class _CustomGamePlayerState extends State<_QuizPlayer> {
  _Scene _scene = _Scene.welcome;
  // Snapshot of the game's questions taken once at init so the
  // sequence is stable for this play even if Firestore replaces the
  // CustomGame doc beneath us mid-session.
  late final List<QuizQuestion> _questions;
  // Tracks which question is currently on screen.
  int _currentQuestionIndex = 0;
  // Parallel to `_questions` — answers[i] is the participant's
  // response to questions[i]. Filled as the participant taps
  // through; submitted in one structured payload at session end.
  final List<String> _answers = [];
  late final String _sessionId;
  late final DateTime _startedAt;
  bool _resultHooksFired = false;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    // `effectiveQuestions` papers over older single-question docs (a
    // single QuizQuestion synthesized from the legacy `prompt` +
    // `options` fields) and the new multi-question docs. We snapshot
    // it here so the sequence is stable for the rest of this play.
    _questions = widget.game.effectiveQuestions;
    // Same pattern as TwineQuestionnaireHost — sessionId joins all the
    // per-play writes (response doc, telemetry event, gameSessions
    // summary, HealthKit snapshot) so researchers can reconstruct one
    // play of one game by one user.
    _sessionId = '${_surveyId}_${_startedAt.millisecondsSinceEpoch}';

    // Game-open telemetry — mirrors the *_opened event TwineGameHost
    // fires for catalog games.
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

  Future<void> _onAnswerTapped(String answer) async {
    // Compute branching upfront so the post-setState completion
    // check sees the same value setState applied. Last question
    // advances to the result scene; earlier questions just bump the
    // index.
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
    // Fire the hook chain on FIRST entry to result; guard so back-
    // navigation to result (e.g. via burger restart) doesn't double-
    // award points.
    if (_resultHooksFired) return;
    _resultHooksFired = true;
    await _fireCompletionHooks();
  }

  Future<void> _fireCompletionHooks() async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    final game = widget.game;

    // 1. Custom games repo — bumps completedCount + stamps
    //    lastCompletedAt so the dashboard tile reflects it.
    if (uid.isNotEmpty) {
      // ignore: unawaited_futures
      CustomGamesRepository.instance.markCompleted(
        uid: uid,
        gameId: game.id,
      );
    }

    // 2. SurveyHooks — writes to surveys/custom_<gameId>/responses,
    //    bumps userData.points + .surveysCompleted, fires immutable
    //    event row. Same plumbing the Twine questionnaires use. The
    //    `questions` array preserves prompt + options + answer per
    //    question for downstream research queries.
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

    // 3. PointsHooks — optimistic UI bump on the dashboard so the
    //    user sees their new total before the Firestore write resolves.
    //    SurveyHooks.submitResponse also bumps points server-side via
    //    OfflineFieldValue.increment, but the local state mirror is
    //    what the home screen reads.
    if (mounted) {
      PointsHooks.applyIncrements(context, {
        'points': game.pointsReward,
        'totalSessions': 1,
      });
    }

    // 4. TelemetryHooks — completion event with the session join key.
    //    Counts only (not the answers themselves) so the events
    //    collection stays PII-clean — the full per-question payload
    //    lives in the surveys response doc above for analysis.
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

    // 5. HealthHooks — wearable snapshot at game end (matches the
    //    Twine hosts' end-game pattern). Stamped with sessionId so
    //    researchers can join it to the rest of the per-play writes.
    if (uid.isNotEmpty) {
      // ignore: unawaited_futures
      HealthHooks.logSnapshot(
        uid: uid,
        gameId: _surveyId,
        sessionId: _sessionId,
      );
    }

    // 6. gameSessions/{sessionId} summary doc — netguage CheckData
    //    equivalent. Same shape TwineQuestionnaireHost writes so a
    //    single query can pull "every play of every game" across both
    //    Twine and custom flows.
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
          // Same `hostType` field TwineQuestionnaireHost / TwineGameHost
          // write so a single query against gameSessions can group plays
          // by host. `Timestamp.fromDate` was changed to
          // OfflineFieldValue.timestampFrom because the queued payload
          // round-trips through Hive — Firestore Timestamps don't
          // survive that encode/decode reliably.
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

/// Mimics the dark gradient + flex-column layout the Twine games use.
/// Header bar at top with title + the same `≡` glyph, scrollable
/// content below.
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
