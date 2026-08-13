// Central launch point for all games. Both the catalog and dashboard favourites
// call this, so the game-id-to-screen mapping is in one place.

import 'package:flutter/material.dart';

import '../dashboard/screens/coming_soon_screen.dart';
import 'bingo_bash_game.dart';
import 'control_game.dart';
import 'dash_diet_twine_game.dart';
import 'dog_quest.dart';
import 'game_completion_signal.dart';
import 'game_feedback.dart';
import 'game_stories.dart';
import 'pill_path.dart';
import 'quiet_landscape.dart';
import 'quiet_minute.dart';
import 'salt_sludge.dart';
import 'vascular_village_game.dart';

// Opens the right game screen. Unknown ids fall back to "Coming Soon".
void launchGameStory(BuildContext context, GameStory game) {
  Widget? screen;
  switch (game.id) {
    case 'dog_quest':
      // 500m default; the in-game difficulty picker adjusts it before GPS starts.
      screen = DogQuestGame(targetDistance: 500);
      break;
    case 'control_daily_checkin':
      screen = const ControlGame();
      break;
    case 'salt_sludge':
      screen = const SaltSludgeGame();
      break;
    case 'bingo_bash':
      screen = const BingoBashGame();
      break;
    case 'dash_diet_game':
      screen = const DashDietTwineGame();
      break;
    case 'vascular_village':
      screen = const VascularVillageGame();
      break;
    case 'quiet_minute':
      // Not in the catalog (showInCatalog: false) but reachable if favourited.
      screen = const QuietMinuteGame();
      break;
    case 'pill_path':
      screen = const PillPathGame();
      break;
    case 'quiet_landscape':
      screen = const QuietLandscapeGame();
      break;
  }
  // Capture navigator before the game opens (context may be gone when it closes).
  final navigator = Navigator.of(context);

  navigator
      .push(
    MaterialPageRoute(
      builder: (_) => screen ?? ComingSoonScreen(featureName: game.title),
    ),
  )
      .then((_) {
    // Show feedback popup only if the game was actually finished.
    // consume() also clears the signal so it can't trigger again.
    final completed = GameCompletionSignal.consume(game.id);
    final hasQuestions = gameFeedbackQuestions.containsKey(game.id);
    debugPrint('GameFeedback: ${game.id} closed - '
        'completed=$completed hasQuestions=$hasQuestions');
    if (completed && hasQuestions) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => GameFeedbackScreen(
            gameId: game.id,
            gameTitle: game.title,
          ),
        ),
      );
    }
  });
}
