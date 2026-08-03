import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/hooks/hooks.dart';

import 'package:cardio_care_quest/core/theme/app_colors.dart';

// BP Trivia - a short multiple-choice quiz about blood pressure. Pick an
// answer, see if it's right, and after the last question your score is
// saved and you earn points. This is a real Flutter screen (not an HTML game).

// The quiz screen. It keeps changing (question to question), so it's stateful.
class BPTriviaScreen extends StatefulWidget {
  const BPTriviaScreen({super.key});

  @override
  State<BPTriviaScreen> createState() => _BPTriviaScreenState();
}

// ---- STATE ----

// Holds the live quiz state: which question we're on, the score, and what
// the player tapped.
class _BPTriviaScreenState extends State<BPTriviaScreen> {
  int _currentQuestionIndex = 0;
  int _score = 0;
  int? _selectedAnswerIndex;
  bool _answered = false;

  /// Per-question correctness, submitted with the score so research analysis
  /// can see which items were right - not just the aggregate.
  final List<Map<String, dynamic>> _answerLog = [];

  /// The 2s "advance to next question" timer. Held so it can be cancelled in
  /// [dispose] - otherwise navigating away mid-question fires setState /
  /// _saveScoreAndShowResults on a disposed State.
  Timer? _advanceTimer;

  // Runs when the screen closes. Cancel the timer so it doesn't fire after
  // we're gone and crash.
  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  // ---- QUESTIONS ----

  // The quiz questions. Each has the answer choices and which one is correct.
  final List<Map<String, dynamic>> _questions = [
    {
      'question': 'What is a normal blood pressure reading?',
      'answers': ['120/80 mmHg', '140/90 mmHg', '100/60 mmHg', '160/100 mmHg'],
      'correctAnswerIndex': 0,
    },
    {
      'question': 'Which of these is a risk factor for high blood pressure?',
      'answers': ['Eating a balanced diet', 'Regular exercise', 'Smoking', 'Getting enough sleep'],
      'correctAnswerIndex': 2,
    },
    {
      'question': 'What does the top number in a blood pressure reading represent?',
      'answers': ['Diastolic pressure', 'Systolic pressure', 'Heart rate', 'Oxygen saturation'],
      'correctAnswerIndex': 1,
    },
    {
      'question': 'Which food is high in sodium and should be limited?',
      'answers': ['Fresh vegetables', 'Processed meats', 'Whole grains', 'Lean protein'],
      'correctAnswerIndex': 1,
    },
    {
      'question': 'How much exercise is recommended per week for adults?',
      'answers': ['30 minutes', '60 minutes', '120 minutes', '150 minutes'],
      'correctAnswerIndex': 3,
    },
  ];

  // ---- ANSWERING ----

  // Runs when the player taps an answer. Marks it right/wrong, records it,
  // then waits 2 seconds before moving to the next question (or the results).
  void _answerQuestion(int selectedIndex) {
    final correctIndex =
        _questions[_currentQuestionIndex]['correctAnswerIndex'] as int;
    final isCorrect = selectedIndex == correctIndex;

    setState(() {
      _answered = true;
      _selectedAnswerIndex = selectedIndex;
      if (isCorrect) {
        _score++;
      }
    });

    // Remember what they picked on this question (for the research data).
    _answerLog.add({
      'questionIndex': _currentQuestionIndex,
      'selectedIndex': selectedIndex,
      'correctIndex': correctIndex,
      'isCorrect': isCorrect,
    });

    // After a short pause, go to the next question or finish up.
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (_currentQuestionIndex < _questions.length - 1) {
        setState(() {
          _currentQuestionIndex++;
          _answered = false;
          _selectedAnswerIndex = null;
        });
      } else {
        _saveScoreAndShowResults();
      }
    });
  }

  // ---- SAVING & RESULTS ----

  // Saves the final score and points to the cloud, then shows the results popup.
  Future<void> _saveScoreAndShowResults() async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isNotEmpty) {
      try {
        // 10 points per correct answer. (An old bug did this backwards and
        // paid out for WRONG answers, so watch that this stays _score * 10.)
        final pointsEarned = _score * 10;
        await DailyLogHooks.logTrivia(
          uid: uid,
          score: _score,
          totalQuestions: _questions.length,
          pointsEarned: pointsEarned,
          answers: List<Map<String, dynamic>>.from(_answerLog),
        );
        if (mounted) {
          // Bump the on-screen points right away so it feels instant, without
          // waiting for the cloud save to come back.
          PointsHooks.applyIncrements(context, {'points': pointsEarned});
        }
      } catch (e) {
        debugPrint('Error saving trivia score: $e');
      }
    }
    _showResults();
  }

  // Pops up "Quiz Complete!" with the final score. "Play Again" closes both
  // the popup and the quiz screen.
  void _showResults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quiz Complete!'),
        content: Text('You scored $_score out of ${_questions.length}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  // ---- UI ----

  // Draws the whole quiz screen: progress bar, the question card, the
  // answer buttons, and the running points total.
  @override
  Widget build(BuildContext context) {
    final question = _questions[_currentQuestionIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('BP Trivia'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: LinearProgressIndicator(
            value: (_currentQuestionIndex + 1) / _questions.length,
            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              'Question ${_currentQuestionIndex + 1}/${_questions.length}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.subtitle,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: AppColors.cardBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  question['question'],
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.title, height: 1.3),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                ),
              ),
            ),
            const Spacer(),
            if (_answered) ...[
              Text(
                _selectedAnswerIndex == question['correctAnswerIndex']
                    ? 'Excellent!'
                    : 'Not quite! Learning is growing.',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _selectedAnswerIndex == question['correctAnswerIndex'] ? AppColors.success : AppColors.error,
                ),
              ),
              const Spacer(),
            ],
            ...List.generate(question['answers'].length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: _buildAnswerButton(index),
              );
            }),
            const Spacer(),
            Text(
              'Points Reward: ${_score * 10}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Builds one answer button. After the player answers, it turns the picked
  // button green (right) or red (wrong), and highlights the correct one.
  Widget _buildAnswerButton(int index) {
    final question = _questions[_currentQuestionIndex];
    final isSelected = _selectedAnswerIndex == index;
    final isCorrect = index == question['correctAnswerIndex'];
    Color buttonColor = AppColors.background;
    Color textColor = AppColors.body;

    if (_answered) {
      if (isSelected) {
        buttonColor = isCorrect ? AppColors.success : AppColors.error;
        textColor = Colors.white;
      } else if (isCorrect) {
        buttonColor = AppColors.success.withValues(alpha: 0.5);
      }
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: textColor,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: _answered && (isSelected || isCorrect) ? Colors.transparent : AppColors.cardBorder,
              width: 2,
            ),
          ),
        ),
        onPressed: _answered ? null : () => _answerQuestion(index),
        child: Text(
          question['answers'][index],
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

