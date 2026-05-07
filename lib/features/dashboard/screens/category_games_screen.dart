// Inner page of the Game Catalog — shown when a category tile is
// tapped. 2-column grid of game tiles for that pillar. Tapping a tile
// opens the [GameDetailDialog] (preview + Play) — same dialog the
// catalog used before, so the play UX is unchanged.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../games/game_stories.dart';
import '../widgets/game_detail_dialog.dart';

class CategoryGamesScreen extends StatelessWidget {
  final GameCategory category;

  const CategoryGamesScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final games =
        GameCatalog.getCatalogGamesByCategory()[category] ?? const [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          category.label,
          style: const TextStyle(color: AppColors.title),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.title),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1,
        ),
        itemCount: games.length,
        itemBuilder: (context, i) {
          final g = games[i];
          return _GameSquareCard(
            game: g,
            onTap: () => showGameDetailDialog(context, g),
          );
        },
      ),
    );
  }
}

class _GameSquareCard extends StatelessWidget {
  final GameStory game;
  final VoidCallback onTap;

  const _GameSquareCard({required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: game.title,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(game.iconData, color: AppColors.primary, size: 44),
                  const SizedBox(height: 12),
                  Text(
                    game.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.title,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
