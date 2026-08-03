// CustomGame - the data for one game a user built themselves in the
// "Design Your Own Game" screen. It's a walk goal or a little quiz.
// Saved in the cloud under this user's own list of games.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../game_stories.dart';

// Which kind of game this is. This picks how it plays.
//   • walk - go for a real walk, tracked by GPS, like Dog Quest.
//            The user picks how far to walk.
//   • quiz - answer some questions, 2 to 4 choices each.
enum CustomGameType { walk, quiz }

// Extra helpers on the game type: a name, a one-liner, and an icon.

extension CustomGameTypeX on CustomGameType {
  String get label {
    switch (this) {
      case CustomGameType.walk:
        return 'Walking quest';
      case CustomGameType.quiz:
        return 'Quick quiz';
    }
  }

  String get tagline {
    switch (this) {
      case CustomGameType.walk:
        return 'Pick a distance, take a walk, earn points based on GPS.';
      case CustomGameType.quiz:
        return 'Ask yourself one question, pick from 2-4 answers.';
    }
  }

  IconData get icon {
    switch (this) {
      case CustomGameType.walk:
        return Icons.directions_walk;
      case CustomGameType.quiz:
        return Icons.quiz_outlined;
    }
  }
}

// One question in a quiz. A quiz has one or more of these. The player
// shows them one at a time and sends all the answers at the end.
class QuizQuestion {
  final String prompt;
  final List<String> options;

  const QuizQuestion({
    required this.prompt,
    this.options = const <String>[],
  });

  // Turn this question into a plain map so it can be saved to the cloud.
  Map<String, dynamic> toMap() => {
        'prompt': prompt,
        'options': options,
      };

  // Build a question back from a saved map. Falls back to safe defaults.
  static QuizQuestion fromMap(Map<dynamic, dynamic> m) {
    final raw = m['options'];
    return QuizQuestion(
      prompt: (m['prompt'] as String?) ?? '',
      options: (raw is List)
          ? raw.whereType<String>().toList()
          : const <String>[],
    );
  }
}

// The whole game and its saved stats (how many times it was finished, etc).
class CustomGame {
  final String id;
  final String title;
  final String description;
  final GameCategory category;
  final int pointsReward;
  final CustomGameType gameType;

  // The quiz questions (one or more). Empty for walk games. Older saved
  // games from before we allowed many questions use the two fields below
  // instead - `effectiveQuestions` smooths over both cases.
  final List<QuizQuestion> questions;

  // Old-style single-question fields. Kept so games saved before the
  // multi-question feature still open. New games leave these empty.
  final String prompt;
  final List<String> options;

  // For walk games: how far to walk, in meters. 0 for a quiz.
  final int targetDistance;

  final DateTime? createdAt;
  final int completedCount;
  final DateTime? lastCompletedAt;

  const CustomGame({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.pointsReward,
    this.gameType = CustomGameType.quiz,
    this.questions = const <QuizQuestion>[],
    this.prompt = '',
    this.options = const <String>[],
    this.targetDistance = 0,
    this.createdAt,
    this.completedCount = 0,
    this.lastCompletedAt,
  });

  // The icon just comes from the category, so there's no icon picker.
  IconData get iconData => category.icon;

  // The real list of questions to play. Uses the new list if it has any;
  // otherwise makes a one-item list from the old fields so old games
  // still work. Empty for walk games.
  List<QuizQuestion> get effectiveQuestions {
    if (questions.isNotEmpty) return questions;
    if (gameType != CustomGameType.quiz) return const <QuizQuestion>[];
    return <QuizQuestion>[
      QuizQuestion(prompt: prompt, options: options),
    ];
  }

  // Pack the whole game into a map so it can be saved to the cloud.
  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category.name,
        'pointsReward': pointsReward,
        'gameType': gameType.name,
        'questions': questions.map((q) => q.toMap()).toList(),
        // Also save the first question the old way, so an older app
        // version can still show at least that one question.
        'prompt': questions.isNotEmpty ? questions.first.prompt : prompt,
        'options': questions.isNotEmpty
            ? questions.first.options
            : options,
        'targetDistance': targetDistance,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt!),
        'completedCount': completedCount,
        if (lastCompletedAt != null)
          'lastCompletedAt': Timestamp.fromDate(lastCompletedAt!),
      };

  // Build a game back from a saved cloud record. Missing bits get safe
  // defaults so a half-empty record still opens instead of crashing.
  static CustomGame fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawOptions = data['options'];
    final options = (rawOptions is List)
        ? rawOptions.whereType<String>().toList()
        : const <String>[];
    final rawQuestions = data['questions'];
    final questions = (rawQuestions is List)
        ? rawQuestions
            .whereType<Map>()
            .map(QuizQuestion.fromMap)
            .toList()
        : const <QuizQuestion>[];
    return CustomGame(
      id: doc.id,
      title: (data['title'] as String?) ?? 'Untitled goal',
      description: (data['description'] as String?) ?? '',
      category: _categoryFromName(data['category'] as String?),
      pointsReward: (data['pointsReward'] as num?)?.toInt() ?? 25,
      gameType: _gameTypeFromName(data['gameType'] as String?),
      questions: questions,
      prompt: (data['prompt'] as String?) ?? '',
      options: options,
      targetDistance: (data['targetDistance'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      completedCount: (data['completedCount'] as num?)?.toInt() ?? 0,
      lastCompletedAt: (data['lastCompletedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Turn a saved category name back into the matching category.
  // Defaults to "exercise" if the name is missing or unknown.
  static GameCategory _categoryFromName(String? name) {
    if (name == null) return GameCategory.exercise;
    for (final c in GameCategory.values) {
      if (c.name == name) return c;
    }
    return GameCategory.exercise;
  }

  // Turn a saved type name ("walk"/"quiz") back into the type.
  // Defaults to quiz if it's missing or unknown.
  static CustomGameType _gameTypeFromName(String? name) {
    if (name == null) return CustomGameType.quiz;
    for (final t in CustomGameType.values) {
      if (t.name == name) return t;
    }
    return CustomGameType.quiz;
  }
}
