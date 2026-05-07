// Inner page for the participant's custom games ("Your Goals"). Same
// shape as [CategoryGamesScreen] but pulls from the live Firestore
// stream so newly-authored goals appear immediately. The empty state
// is reachable in theory (the catalog tile is hidden when empty) but
// guarded here in case the participant deletes their last custom game
// while this screen is open.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/user_data_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../games/custom_games/custom_game.dart';
import '../../games/custom_games/custom_games_repository.dart';
import '../widgets/game_detail_dialog.dart';

class CustomGamesScreen extends StatelessWidget {
  const CustomGamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.select<UserDataProvider, String>((p) => p.uid);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Your Goals',
          style: TextStyle(color: AppColors.title),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.title),
      ),
      body: StreamBuilder<List<CustomGame>>(
        stream: uid.isEmpty
            ? const Stream<List<CustomGame>>.empty()
            : CustomGamesRepository.instance.watch(uid),
        builder: (context, snap) {
          final games = snap.data ?? const <CustomGame>[];
          if (games.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  "You haven't designed any goals yet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.subtitle,
                    fontSize: 16,
                  ),
                ),
              ),
            );
          }
          return GridView.builder(
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
              return _CustomGameSquareCard(
                game: g,
                onTap: () => showCustomGameDetailDialog(context, g),
              );
            },
          );
        },
      ),
    );
  }
}

class _CustomGameSquareCard extends StatelessWidget {
  final CustomGame game;
  final VoidCallback onTap;

  const _CustomGameSquareCard({required this.game, required this.onTap});

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
                      fontSize: 14,
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
