import 'package:flutter/material.dart';
import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/services/offline_queue.dart';

import 'package:cardio_care_quest/core/theme/app_colors.dart';

class BPTriviaScreen extends StatefulWidget {
  const BPTriviaScreen({super.key});

  @override
  State<BPTriviaScreen> createState() => _BPTriviaScreenState();
}

class _BPTriviaScreenState extends State<BPTriviaScreen> {
  int _currentQuestionIndex = 0;
  int _score = 0;
  int? _selectedAnswerIndex;
  bool _answered = false;

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

  void _answerQuestion(int selectedIndex) {
    setState(() {
      _answered = true;
      _selectedAnswerIndex = selectedIndex;
      if (selectedIndex == _questions[_currentQuestionIndex]['correctAnswerIndex']) {
        _score++;
      }
    });

    Timer(const Duration(seconds: 2), () {
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

  Future<void> _saveScoreAndShowResults() async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isNotEmpty) {
      try {
        final xpEarned = (_questions.length - _score) * 10;
        final eventId = const Uuid().v4();
        await GetIt.instance<OfflineQueue>().enqueueBatch([
          PendingOp.update('${FirestorePaths.userData}/$uid', {
            'points': OfflineFieldValue.increment(xpEarned),
          }),
          PendingOp.set(
            '${FirestorePaths.events}/$eventId',
            {
              'id': eventId,
              'userId': uid,
              'event': 'trivia_completed',
              'score': _score,
              'totalQuestions': _questions.length,
              'xpEarned': xpEarned,
              'timestamp': OfflineFieldValue.nowTimestamp(),
              'syncedAt': OfflineFieldValue.nowTimestamp(),
            },
          ),
        ]);
        if (mounted) {
          Provider.of<UserDataProvider>(context, listen: false).fetchUserData();
        }
      } catch (e) {
        debugPrint('Error saving trivia score: $e');
      }
    }
    _showResults();
  }

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
              'XP Reward: ${(_questions.length - _score) * 10}',
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

