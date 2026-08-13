// Data for one user-created game (walk goal or quiz).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../game_stories.dart';

// walk = GPS-tracked walk (like Dog Quest); quiz = answer some questions.
enum CustomGameType { walk, quiz }

// Helpers: display name, tagline, and icon for each game type.
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

// One quiz question with its answer choices.
class QuizQuestion {
  final String prompt;
  final List<String> options;

  const QuizQuestion({
    required this.prompt,
    this.options = const <String>[],
  });

  // Convert to a map for cloud storage.
  Map<String, dynamic> toMap() => {
        'prompt': prompt,
        'options': options,
      };

  // Rebuild a question from a saved map. Missing fields get safe defaults.
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

// A user-created game and its saved play stats.
class CustomGame {
  final String id;
  final String title;
  final String description;
  final GameCategory category;
  final int pointsReward;
  final CustomGameType gameType;

  // Quiz questions. Empty for walk games. Old saves used `prompt`/`options`
  // instead; `effectiveQuestions` handles both.
  final List<QuizQuestion> questions;

  // Legacy single-question fields kept for backward compatibility.
  final String prompt;
  final List<String> options;

  // Walk goal in meters. 0 for quiz games.
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

  IconData get iconData => category.icon;

  // Returns the questions to play. Falls back to the old single-question
  // fields for saves from before multi-question support was added.
  List<QuizQuestion> get effectiveQuestions {
    if (questions.isNotEmpty) return questions;
    if (gameType != CustomGameType.quiz) return const <QuizQuestion>[];
    return <QuizQuestion>[
      QuizQuestion(prompt: prompt, options: options),
    ];
  }

  // Convert the game to a map for cloud storage.
  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category.name,
        'pointsReward': pointsReward,
        'gameType': gameType.name,
        'questions': questions.map((q) => q.toMap()).toList(),
        // Also write old-style fields so older app versions can still open it.
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

  // Rebuild a game from a cloud record. Missing fields get safe defaults.
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

  // Parse a saved category name. Defaults to "exercise" if unknown.
  static GameCategory _categoryFromName(String? name) {
    if (name == null) return GameCategory.exercise;
    for (final c in GameCategory.values) {
      if (c.name == name) return c;
    }
    return GameCategory.exercise;
  }

  // Parse a saved game type name. Defaults to quiz if unknown.
  static CustomGameType _gameTypeFromName(String? name) {
    if (name == null) return CustomGameType.quiz;
    for (final t in CustomGameType.values) {
      if (t.name == name) return t;
    }
    return CustomGameType.quiz;
  }
}
