// GameDetailDialog — modal preview shown when a game is tapped in the
// catalog. Mirrors the netguage popup pattern: title, large iconography,
// narrative blurb, then a heart (favourite toggle), Play, and Close.
//
// Accepts EITHER a catalog GameStory OR a participant-authored
// CustomGame. Both follow the same dialog shape; the Play button
// dispatches to the right launcher (catalog → launchGameStory; custom
// → CustomGamePlayer).

import 'package:flutter/material.dart';

import '../../../core/services/favorites_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../games/custom_games/custom_game.dart';
import '../../games/custom_games/custom_game_player.dart';
import '../../games/game_launcher.dart';
import '../../games/game_stories.dart';

/// Show the [GameDetailDialog] for a catalog game. Returns when the
/// user dismisses the modal (Close, back gesture, or barrier tap).
/// Play is fire-and-forget — it pushes a new route and the dialog
/// closes itself first so the gameplay screen replaces it cleanly.
Future<void> showGameDetailDialog(BuildContext context, GameStory game) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => GameDetailDialog(game: game),
  );
}

/// Show the same dialog for a participant-authored custom game. Same
/// layout, different launcher.
Future<void> showCustomGameDetailDialog(
    BuildContext context, CustomGame game) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => GameDetailDialog.custom(customGame: game),
  );
}

class GameDetailDialog extends StatelessWidget {
  final GameStory? game;
  final CustomGame? customGame;

  const GameDetailDialog({super.key, required GameStory this.game})
      : customGame = null;

  const GameDetailDialog.custom({super.key, required CustomGame this.customGame})
      : game = null;

  bool get _isCustom => customGame != null;
  String get _title => _isCustom ? customGame!.title : game!.title;
  String get _shortDescription =>
      _isCustom ? customGame!.description : game!.shortDescription;
  IconData get _iconData =>
      _isCustom ? customGame!.iconData : game!.iconData;
  String get _favoriteId => _isCustom ? customGame!.id : game!.id;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                _title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.title,
                ),
              ),
              const SizedBox(height: 16),

              // Large iconography. Centered, sized like the netguage
              // silhouettes so the dialog reads at a glance.
              Center(
                child: Container(
                  width: 110,
                  height: 110,
                  alignment: Alignment.center,
                  child: Icon(
                    _iconData,
                    size: 84,
                    color: AppColors.title,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Single short tagline — matches netguage's popup
              // pattern (one paragraph of body text, no separate
              // long narrative). The longer per-game narrative still
              // lives in `game_stories.dart` for any future "Learn
              // more" surface; it just isn't rendered here, since
              // older participants found the wall-of-text dialog
              // hard to read before deciding to play.
              if (_shortDescription.isNotEmpty) ...[
                Text(
                  _shortDescription,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.title,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Bottom action row — heart on the left, Play + Close on
              // the right. Layout matches the netguage reference.
              Row(
                children: [
                  _FavoriteHeartButton(gameId: _favoriteId),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      // Close the dialog FIRST so the new route doesn't
                      // sit underneath a translucent barrier — feels
                      // snappier and avoids a frame of dimmed content.
                      Navigator.of(context).pop();
                      if (_isCustom) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CustomGamePlayer(game: customGame!),
                          ),
                        );
                      } else {
                        launchGameStory(context, game!);
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text(
                      'Play',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Heart icon that toggles the game's favourite state. Filled red when
/// favourited, outlined grey otherwise. Listens to
/// [FavoritesService.favorites] so it reflects the change instantly
/// without needing the parent dialog to rebuild.
class _FavoriteHeartButton extends StatelessWidget {
  final String gameId;

  const _FavoriteHeartButton({required this.gameId});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: FavoritesService.instance.favorites,
      builder: (context, favorites, _) {
        final isFav = favorites.contains(gameId);
        return IconButton(
          tooltip: isFav ? 'Remove from favourites' : 'Add to favourites',
          onPressed: () {
            FavoritesService.instance.toggle(gameId);
          },
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            color: isFav ? Colors.redAccent : AppColors.subtitle,
            size: 28,
          ),
        );
      },
    );
  }
}
