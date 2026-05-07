// Shared game-launch routing.
//
// Both the Game Catalog (via GameDetailDialog's Play button) and the
// dashboard's Favourites strip (via direct tap, no dialog) need to push
// the right Twine host route for a given GameStory id. Pulling that
// switch into one place keeps the two call sites in sync.

import 'package:flutter/material.dart';

import '../dashboard/screens/coming_soon_screen.dart';
import 'bingo_bash_game.dart';
import 'control_game.dart';
import 'dash_diet_twine_game.dart';
import 'dog_quest.dart';
import 'game_stories.dart';
import 'quiet_minute.dart';
import 'salt_sludge.dart';
import 'vascular_village_game.dart';

/// Push the correct gameplay screen for [game]. Falls back to
/// [ComingSoonScreen] for any id that hasn't been wired up yet so a
/// missing route can't crash the dry-run.
void launchGameStory(BuildContext context, GameStory game) {
  Widget? screen;
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
  }
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => screen ?? ComingSoonScreen(featureName: game.title),
    ),
  );
}
