import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../games/game_stories.dart';
import '../../games/dog_quest.dart';
import 'coming_soon_screen.dart';
import 'package:cardio_care_quest/shared/widgets/game_narrative_card.dart';

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
        child: ListView.separated(
          itemCount: allGames.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final game = allGames[index];
            return GameNarrativeCard(
              game: game,
              onPlayTap: () {
                if (game.id == 'dog_quest') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DogQuestGame(targetDistance: 500),
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
