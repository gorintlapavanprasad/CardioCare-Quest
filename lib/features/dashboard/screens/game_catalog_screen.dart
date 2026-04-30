import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../games/game_stories.dart';
import '../../games/dog_quest.dart';
import '../../games/control_game.dart';
import '../../games/salt_sludge.dart';
import '../../games/bingo_bash_game.dart';
import '../../games/dash_diet_twine_game.dart';
import '../../games/vascular_village_game.dart';
import 'coming_soon_screen.dart';

class GameCatalogScreen extends StatelessWidget {
  const GameCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final allGames = GameCatalog.games.values.toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Game Catalog',
          style: TextStyle(color: AppColors.title),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.title),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1,
          ),
          itemCount: allGames.length,
          itemBuilder: (context, index) {
            final game = allGames[index];
            return _GameSquareCard(
              game: game,
              onTap: () {
                if (game.id == 'dog_quest') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DogQuestGame(targetDistance: 500),
                    ),
                  );
                } else if (game.id == 'control_daily_checkin') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ControlGame(),
                    ),
                  );
                } else if (game.id == 'salt_sludge') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SaltSludgeGame(),
                    ),
                  );
                } else if (game.id == 'bingo_bash') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BingoBashGame(),
                    ),
                  );
                } else if (game.id == 'dash_diet_game') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DashDietTwineGame(),
                    ),
                  );
                } else if (game.id == 'vascular_village') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VascularVillageGame(),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ComingSoonScreen(featureName: game.title),
                    ),
                  );
                }
              },
            );
          },
        ),
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
    final Color cardColor =
        Color(int.parse(game.color.replaceFirst('#', '0xFF')));

    return Material(
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
                color: cardColor.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(game.emoji, style: const TextStyle(fontSize: 44)),
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
    );
  }
}
