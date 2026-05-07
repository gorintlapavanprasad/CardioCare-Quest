// CustomGame — model for a participant-authored personal goal/quest
// created via the "Design Your Own Game" flow. Stored at
// userData/{uid}/customGames/{gameId}.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../game_stories.dart';

/// Determines which player + which hooks chain a custom game uses.
///
///   • walk  — GPS-tracked movement quest. Uses LocationDispatcher +
///             MovementHooks (pushPing / endSession), exactly like
///             Dog Quest. The participant sets a target distance.
///   • quiz  — Multi-question prompt with 2-4 options per question.
///             Uses SurveyHooks.submitResponse + PointsHooks. The
///             participant cycles through questions sequentially and
///             one play submits one structured answers payload.
enum CustomGameType { walk, quiz }

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

/// One question within a quiz-type custom game. A game has 1..N of
/// these; the player walks through them sequentially and the answers
/// are submitted in one structured payload at the end of play.
class QuizQuestion {
  final String prompt;
  final List<String> options;

  const QuizQuestion({
    required this.prompt,
    this.options = const <String>[],
  });

  Map<String, dynamic> toMap() => {
        'prompt': prompt,
        'options': options,
      };

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

class CustomGame {
  final String id;
  final String title;
  final String description;
  final GameCategory category;
  final int pointsReward;
  final CustomGameType gameType;

  /// Quiz-type questions (one or more). Empty for walk-type. New
  /// games always populate this list; older docs that pre-date the
  /// multi-question feature only have the legacy `prompt`+`options`
  /// scalars below — `effectiveQuestions` papers over both shapes.
  final List<QuizQuestion> questions;

  /// Legacy single-question fields. Kept readable so existing
  /// participant docs from before the multi-question feature still
  /// load. New games leave these empty and use `questions` above.
  final String prompt;
  final List<String> options;

  /// Walk-type field (meters). 0 for quiz-type.
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

  /// Icon derived from the category — keeps the build form simpler
  /// (no icon picker) and matches the rest of the catalog where the
  /// pillar icon already represents the activity type.
  IconData get iconData => category.icon;

  /// Single source of truth for "what does this quiz ask?". Returns
  /// the multi-question list when present; otherwise synthesises a
  /// 1-element list from the legacy `prompt`+`options` so older
  /// single-question games still play. Empty for walk-type games.
  List<QuizQuestion> get effectiveQuestions {
    if (questions.isNotEmpty) return questions;
    if (gameType != CustomGameType.quiz) return const <QuizQuestion>[];
    return <QuizQuestion>[
      QuizQuestion(prompt: prompt, options: options),
    ];
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category.name,
        'pointsReward': pointsReward,
        'gameType': gameType.name,
        'questions': questions.map((q) => q.toMap()).toList(),
        // Legacy fields — still written so older clients that haven't
        // shipped the multi-question reader yet can still display the
        // first question. Sourced from `questions[0]` when present.
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

  static GameCategory _categoryFromName(String? name) {
    if (name == null) return GameCategory.exercise;
    for (final c in GameCategory.values) {
      if (c.name == name) return c;
    }
    return GameCategory.exercise;
  }

  static CustomGameType _gameTypeFromName(String? name) {
    if (name == null) return CustomGameType.quiz;
    for (final t in CustomGameType.values) {
      if (t.name == name) return t;
    }
    return CustomGameType.quiz;
  }
}
