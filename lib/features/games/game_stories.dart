// All game metadata (title, blurb, benefits, colour, icon). No gameplay.
library;

import 'package:flutter/material.dart';

// Health topic a game belongs to. Used to group games in the catalog.
enum GameCategory {
  exercise,
  diet,
  medication,
  measurements,
  education,
}

extension GameCategoryX on GameCategory {
  String get label {
    switch (this) {
      case GameCategory.exercise:
        return 'Exercise';
      case GameCategory.diet:
        return 'Diet';
      case GameCategory.medication:
        return 'Medication';
      case GameCategory.measurements:
        return 'Measurements';
      case GameCategory.education:
        return 'Education';
    }
  }

  IconData get icon {
    switch (this) {
      case GameCategory.exercise:
        return Icons.directions_walk;
      case GameCategory.diet:
        return Icons.restaurant;
      case GameCategory.medication:
        return Icons.medication;
      case GameCategory.measurements:
        return Icons.monitor_heart_outlined;
      case GameCategory.education:
        return Icons.school;
    }
  }
}

// All display info for a single game. Just data, no logic.
class GameStory {
  final String id;
  final String title;
  final String shortDescription;
  final String narrative;
  final String medicalContext;
  final List<String> benefits;
  final String emoji;
  final IconData iconData; // Mono Material icon used by game_catalog_screen
  final String color; // Hex color for card
  final String status; // 'active' or 'coming_soon'
  final GameCategory category; // Pillar this game lives under in the catalog
  // When false, game is hidden from the catalog grid. Use for games only
  // reachable from a specific dashboard widget (e.g. the BP log).
  final bool showInCatalog;

  GameStory({
    required this.id,
    required this.title,
    required this.shortDescription,
    required this.narrative,
    required this.medicalContext,
    required this.benefits,
    required this.emoji,
    required this.iconData,
    required this.color,
    required this.status,
    required this.category,
    this.showInCatalog = true,
  });
}

// Master list of every game, with helpers to filter by status or visibility.
class GameCatalog {
  static final Map<String, GameStory> games = {
    'dog_quest': GameStory(
      id: 'dog_quest',
      title: 'Dog Walking',
      shortDescription: 'Move at a pace that works for you',
      narrative: '''
Your walking companion goes with you every day. They are a small reminder that showing up matters, even when the distance is short.

When you complete a quest, your streak and progress grow. If you miss a day, you simply come back and continue.

Each movement counts. Choose the distance that is safe and realistic for you right now.
      ''',
      medicalContext:
          'When your body moves, your heart rate rises gently. Your blood vessels expand to deliver oxygen to your muscles. Practiced regularly, that expansion helps vessels stay flexible. Flexible vessels mean lower resistance. Lower resistance means lower pressure.',
      benefits: [
        'Reduces blood pressure naturally',
        'Strengthens heart muscle',
        'Improves circulation',
        'Builds consistency',
      ],
      emoji: '🐕‍🦺',
      iconData: Icons.pets,
      color: '#2d7d6d',
      status: 'active',
      category: GameCategory.exercise,
    ),

    'bingo_bash': GameStory(
      id: 'bingo_bash',
      title: 'Bingo Bash',
      shortDescription: 'A fun way to learn about heart health',
      narrative: '''
Who said learning can't be fun? Bingo Bash is a game of chance that tests your knowledge on heart-healthy habits. 

Each square you mark off is a step towards a better understanding of your cardiovascular system. Play with friends, family, or on your own!
      ''',
      medicalContext:
          'Gamification of health education has been shown to increase engagement and knowledge retention. This game focuses on key concepts of hypertension management in an accessible format.',
      benefits: [
        'Learn about hypertension',
        'Reinforce healthy habits',
        'Fun and engaging',
        'Share with family',
      ],
      emoji: '🅱️',
      iconData: Icons.casino,
      color: '#d4a574',
      status: 'active',
      category: GameCategory.education,
    ),

    'dash_diet_game': GameStory(
      id: 'dash_diet_game',
      title: 'DASH Diet Game',
      shortDescription: 'Learn the principles of the DASH diet',
      narrative: '''
The DASH diet is a proven way to help control high blood pressure. This game will guide you through the principles of the diet in a fun and interactive way.

Learn to make smart food choices, create balanced meals, and build a heart-healthy eating plan that you can stick with.
      ''',
      medicalContext:
          'The DASH (Dietary Approaches to Stop Hypertension) diet is a flexible and balanced eating plan that is promoted by the National Heart, Lung, and Blood Institute to do exactly that: stop hypertension.',
      benefits: [
        'Learn the DASH diet',
        'Make healthier food choices',
        'Create balanced meals',
        'Lower blood pressure',
      ],
      emoji: '🥗',
      iconData: Icons.restaurant_menu,
      color: '#2d7d6d',
      status: 'active',
      category: GameCategory.diet,
    ),

    'salt_sludge': GameStory(
      id: 'salt_sludge',
      title: 'Salt Sludge',
      shortDescription: 'Five days of food choices inside your artery',
      narrative: '''
Watch what really happens inside your arteries when you eat. Each day you choose between two foods. Potassium-rich choices clear the sludge. High-sodium choices add to it.

Five days. Five meals. One artery.
      ''',
      medicalContext:
          'Sodium pulls water into the bloodstream, raising volume and pressure on artery walls; potassium helps the kidneys flush sodium back out. Salt Sludge dramatizes this trade-off using everyday foods so the mechanism is concrete instead of abstract.',
      benefits: [
        'See how foods affect arteries',
        'Learn which foods clear sodium',
        'Practice quick food decisions',
        'Make the science concrete',
      ],
      emoji: '🧂',
      iconData: Icons.science,
      color: '#546e7a',
      status: 'active',
      category: GameCategory.diet,
    ),

    // Control condition for the study. Intentionally plain.
    'control_daily_checkin': GameStory(
      id: 'control_daily_checkin',
      title: 'Daily Check-In',
      shortDescription: 'A short set of questions about your day',
      narrative: '''
A few short questions about how you are feeling today, what you ate, and how well you slept.

There are no right or wrong answers. Your responses help the research team understand how the program is working for you.
      ''',
      medicalContext:
          'A daily self-report check-in is a common research instrument for tracking adherence, mood, and self-care behaviors over time without requiring active participation in a structured game.',
      benefits: [
        'Quick to complete',
        'Helps the research team',
        'Plain language',
        'No game pressure',
      ],
      emoji: '📋',
      iconData: Icons.checklist,
      color: '#4a5b80',
      status: 'active',
      category: GameCategory.measurements,
    ),

    'vascular_village': GameStory(
      id: 'vascular_village',
      title: 'Vascular Village',
      shortDescription: 'Build a healthy village for your heart',
      narrative: '''
Your cardiovascular system is like a village, with your heart as the central hub. In Vascular Village, you'll learn how different lifestyle choices affect the health of your village.

Make choices about diet, exercise, and stress management to help your village thrive and see the immediate impact on your villagers' happiness and health.
      ''',
      medicalContext:
          'This game uses a city-building metaphor to explain the complex interplay of factors that contribute to cardiovascular health. It simplifies concepts like cholesterol, blood pressure, and inflammation into relatable game mechanics.',
      benefits: [
        'Understand complex health concepts',
        'See impact of lifestyle choices',
        'Learn about risk factors',
        'Holistic view of heart health',
      ],
      emoji: '🏘️',
      iconData: Icons.holiday_village,
      color: '#1b7373',
      status: 'active',
      category: GameCategory.education,
    ),

    // BP capture after a calming activity. Hidden from the catalog so the
    // entry flow is only reached from the dashboard's "latest reading" card.
    'quiet_minute': GameStory(
      id: 'quiet_minute',
      title: 'Blood Pressure Log',
      shortDescription: 'A short rest, then your blood pressure',
      narrative: '''
Sit somewhere quiet. Breathe slowly for two minutes. Then take your blood pressure with your cuff and enter the numbers.

Your reading is most accurate when you are calm.
      ''',
      medicalContext:
          'Clinical guidelines recommend resting quietly for several minutes before measuring blood pressure. Activity, stress, and recent caffeine can all push systolic readings up by 10-20 mmHg. The two-minute breathing exercise helps return your heart rate and pressure to a steadier baseline so the reading better reflects your everyday state.',
      benefits: [
        'More accurate BP readings',
        'A short calming pause',
        'Tracks your readings over time',
        'Quick and gentle',
      ],
      emoji: '🧘',
      iconData: Icons.self_improvement,
      color: '#3a6a94',
      status: 'active',
      category: GameCategory.measurements,
      showInCatalog: false,
    ),

    // Saves to localStorage for now. Future: wire through SurveyHooks.
    'pill_path': GameStory(
      id: 'pill_path',
      title: 'Pill Path',
      shortDescription: 'Mark your daily medicine and watch the path build',
      narrative: '''
Each day you take your medicine, you tap a pill on your path. After seven days the path is complete and a gentle celebration plays. You can also mark a pill as caregiver-assisted on days when someone helped.

The path builds even on days you missed - those days simply stay empty. The point is honest tracking, not a perfect streak.
      ''',
      medicalContext:
          'Daily adherence to blood-pressure medication is the single largest controllable factor in long-term hypertension outcomes. Tracking adherence - including caregiver assistance - gives the care team a realistic view of how the regimen is working in real life rather than in clinic.',
      benefits: [
        'Build a daily medication habit',
        'Track honest adherence',
        'Acknowledge caregiver help',
        'Visual reward each week',
      ],
      emoji: '💊',
      iconData: Icons.medication,
      color: '#2d7d6d',
      status: 'active',
      category: GameCategory.medication,
    ),

    // Not in the catalog. Vascular Village launches this via the JS bridge
    // to capture a BP reading mid-game.
    'quiet_landscape': GameStory(
      id: 'quiet_landscape',
      title: 'Quiet Landscape',
      shortDescription: 'Breathing scene + BP capture (in-village)',
      narrative: '''
Sixteen slow breaths over a calm landscape. The scene shifts as you breathe - clouds drift, light moves. When the sequence ends you record your cuff reading.
      ''',
      medicalContext:
          'Slow paced breathing engages the parasympathetic nervous system, lowering heart rate and softening vessel tone. Practicing this before a measurement returns the reading closer to your true resting baseline rather than capturing a stressed spike.',
      benefits: [
        'Longer settle before reading',
        'Calmer baseline',
        'Visual breath pacing',
      ],
      emoji: '🌅',
      iconData: Icons.spa,
      color: '#3a6a94',
      status: 'active',
      showInCatalog: false,
      category: GameCategory.medication,
    ),
  };

  // All playable games.
  static List<GameStory> getActiveGames() {
    return games.values.where((g) => g.status == 'active').toList();
  }

  // Games marked "coming soon".
  static List<GameStory> getComingSoonGames() {
    return games.values.where((g) => g.status == 'coming_soon').toList();
  }

  // Look up one game by id.
  static GameStory? getGame(String id) {
    return games[id];
  }

  // Active games visible in the catalog (excludes showInCatalog: false).
  static List<GameStory> getCatalogGames() {
    return games.values
        .where((g) => g.status == 'active' && g.showInCatalog)
        .toList();
  }

  // Catalog games bucketed by category in a fixed order. Empty categories omitted.
  static Map<GameCategory, List<GameStory>> getCatalogGamesByCategory() {
    final all = getCatalogGames();
    final byCat = <GameCategory, List<GameStory>>{};
    for (final cat in GameCategory.values) {
      final inCat = all.where((g) => g.category == cat).toList();
      if (inCat.isNotEmpty) byCat[cat] = inCat;
    }
    return byCat;
  }
}
