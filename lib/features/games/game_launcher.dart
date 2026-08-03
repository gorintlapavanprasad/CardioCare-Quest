// One place that opens the right game screen when you tap "Play".
//
// Both the game catalog and the dashboard's favourites use this, so keeping
// the "which game id opens which screen" list here means they never disagree.

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

// Opens the screen for the given game. If a game id isn't hooked up yet,
// it shows a friendly "Coming Soon" page instead of crashing.
void launchGameStory(BuildContext context, GameStory game) {
  Widget? screen;
  // Pick the matching game screen based on the game's id.
  switch (game.id) {
    case 'dog_quest':
      // 500m default for the catalog launch; in-game scene 2 lets the
      // player pick easy/medium/hard before tracking actually starts.
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
      // Hidden from the catalog (`showInCatalog: false`) but reachable
      // here in case it's ever favourited via some other entry point.
      screen = const QuietMinuteGame();
      break;
    case 'pill_path':
      screen = const PillPathGame();
      break;
    case 'quiet_landscape':
      screen = const QuietLandscapeGame();
      break;
  }
  // Grab the navigator now so we can still use it after the game closes,
  // even though the little preview popup's context is gone by then.
  final navigator = Navigator.of(context);

  // Actually open the chosen screen; fall back to "Coming Soon" if none matched.
  navigator
      .push(
    MaterialPageRoute(
      builder: (_) => screen ?? ComingSoonScreen(featureName: game.title),
    ),
  )
      .then((_) {
    // When the game closes, ask the four short questions - but only if the
    // player actually finished the game and it has feedback questions set up.
    // consume() always clears this game's signal so nothing lingers.
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
