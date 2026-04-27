/// Game Stories & Narrative Content
/// This is the central hub for all game narratives and stories
/// Used to display rich narrative content without needing videos
library;

class GameStory {
  final String id;
  final String title;
  final String shortDescription;
  final String narrative;
  final String medicalContext;
  final List<String> benefits;
  final String emoji;
  final String color; // Hex color for card
  final String status; // 'active' or 'coming_soon'

  GameStory({
    required this.id,
    required this.title,
    required this.shortDescription,
    required this.narrative,
    required this.medicalContext,
    required this.benefits,
    required this.emoji,
    required this.color,
    required this.status,
  });
}

class GameCatalog {
  static final Map<String, GameStory> games = {
    // ─── ACTIVE GAME ───
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
      color: '#2d7d6d',
      status: 'active',
    ),

    // ─── COMING SOON GAMES (from assets) ───
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
      color: '#d4a574',
      status: 'coming_soon',
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
      color: '#2d7d6d',
      status: 'coming_soon',
    ),

    'salt_sludge': GameStory(
      id: 'salt_sludge',
      title: 'Salt Sludge',
      shortDescription: 'Understand the impact of sodium on your body',
      narrative: '''
Too much salt can be a sneaky enemy in your diet. In "Salt Sludge," you'll visualize how excess sodium affects your blood vessels and your heart.

This interactive story will help you become more mindful of your salt intake and empower you to make lower-sodium choices.
      ''',
      medicalContext:
          'High sodium intake contributes to high blood pressure by causing the body to retain water, which puts extra strain on the heart and blood vessels. Reducing sodium is a critical component of hypertension management.',
      benefits: [
        'Visualize sodium\'s effects',
        'Become mindful of salt intake',
        'Make lower-sodium choices',
        'Understand food labels',
      ],
      emoji: '🧂',
      color: '#546e7a',
      status: 'coming_soon',
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
      color: '#1b7373',
      status: 'coming_soon',
    ),
  };

  // Get all active games
  static List<GameStory> getActiveGames() {
    return games.values.where((g) => g.status == 'active').toList();
  }

  // Get all coming soon games
  static List<GameStory> getComingSoonGames() {
    return games.values.where((g) => g.status == 'coming_soon').toList();
  }

  // Get game by ID
  static GameStory? getGame(String id) {
    return games[id];
  }
}
