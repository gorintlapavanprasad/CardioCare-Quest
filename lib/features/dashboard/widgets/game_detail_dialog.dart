// Game preview popup: title, icon, short blurb, heart, Play, and Close.
// Works for both built-in and custom games.

import 'package:flutter/material.dart';

import '../../../core/services/favorites_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../games/custom_games/custom_game.dart';
import '../../games/custom_games/custom_game_player.dart';
import '../../games/game_launcher.dart';
import '../../games/game_stories.dart';

// Opens the preview popup for a built-in game.
Future<void> showGameDetailDialog(BuildContext context, GameStory game) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => GameDetailDialog(game: game),
  );
}

// Same popup but for a custom game.
Future<void> showCustomGameDetailDialog(
    BuildContext context, CustomGame game) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => GameDetailDialog.custom(customGame: game),
  );
}

// The popup widget. Holds either a catalog game or a custom game.
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
              Text(
                _title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.title,
                ),
              ),
              const SizedBox(height: 16),

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

              // Short description only - a wall of text was hard for older users.
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

              Row(
                children: [
                  _FavoriteHeartButton(gameId: _favoriteId),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      // Close first so the game doesn't open under the barrier.
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

// Star button: filled when favourited, outline when not. Updates instantly on tap.
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
            isFav ? Icons.star_rounded : Icons.star_border_rounded,
            color: isFav ? Colors.amber : AppColors.subtitle,
            size: 30,
          ),
        );
      },
    );
  }
}
