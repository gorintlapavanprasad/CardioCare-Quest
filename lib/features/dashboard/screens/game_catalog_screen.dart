// Game Catalog screen — flat grid of category tiles.
//
// Earlier this screen used collapsible accordion sections (one per
// behaviour-change pillar) plus a custom-games accordion at the
// bottom. The accordion model required participants to expand /
// collapse to navigate, which the research team flagged as poor
// accessibility for older or motor-impaired participants. We now
// surface each category as a flat tile in a 2-column grid; tapping a
// tile pushes a dedicated [CategoryGamesScreen] showing the games in
// that pillar. The participant's custom games appear as an extra
// "Your Goals" tile (only when they have any) which opens
// [CustomGamesScreen]. Tile → list → detail dialog → play is one
// linear path with no expand/collapse model required.
//
// `quiet_minute` is intentionally hidden from this screen via
// `showInCatalog: false` in game_stories.dart so the BP-capture flow
// stays exclusively reachable from the dashboard's latest-BP card.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/user_data_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../games/custom_games/custom_game.dart';
import '../../games/custom_games/custom_games_repository.dart';
import '../../games/game_stories.dart';
import 'category_games_screen.dart';
import 'custom_games_screen.dart';

class GameCatalogScreen extends StatelessWidget {
  const GameCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final byCategory = GameCatalog.getCatalogGamesByCategory();
    final categories = byCategory.keys.toList();
    final uid = context.select<UserDataProvider, String>((p) => p.uid);

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
      // Hides the "Your Goals" tile entirely until the participant has
      // authored at least one custom game. Empty stream when uid hasn't
      // loaded yet so the catalog renders immediately with just the
      // pillars and the goals tile pops in once auth + custom-games
      // hydrate.
      body: StreamBuilder<List<CustomGame>>(
        stream: uid.isEmpty
            ? const Stream<List<CustomGame>>.empty()
            : CustomGamesRepository.instance.watch(uid),
        builder: (context, snap) {
          final customGames = snap.data ?? const <CustomGame>[];

          final tiles = <Widget>[
            for (final cat in categories)
              _CatalogTile(
                icon: cat.icon,
                label: cat.label,
                count: byCategory[cat]!.length,
                iconColor: AppColors.primary,
                iconBg: AppColors.primary.withValues(alpha: 0.1),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryGamesScreen(category: cat),
                  ),
                ),
              ),
            if (customGames.isNotEmpty)
              _CatalogTile(
                // Yellow accent + sparkle icon mirrors the old
                // _CustomHeader so participants who already learned
                // "yellow = my own goals" still recognise it.
                icon: Icons.auto_awesome_outlined,
                label: 'Your Goals',
                count: customGames.length,
                iconColor: const Color(0xFFb88616),
                iconBg: const Color(0xFFfde725).withValues(alpha: 0.2),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CustomGamesScreen(),
                  ),
                ),
              ),
          ];

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1,
            ),
            itemCount: tiles.length,
            itemBuilder: (context, i) => tiles[i],
          );
        },
      ),
    );
  }
}

/// Square catalog tile — icon medallion + label + count. Used for both
/// behaviour-change pillars and the participant's "Your Goals" bucket.
/// Whole tile is one big InkWell so the catalog stays navigable for
/// participants with limited motor control. A `Semantics` wrapper
/// flattens the icon/label/count into a single screen-reader
/// announcement ("Exercise, 1 game") instead of three separate ones.
class _CatalogTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color iconColor;
  final Color iconBg;
  final VoidCallback onTap;

  const _CatalogTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.iconColor,
    required this.iconBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $count ${count == 1 ? "game" : "games"}',
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: iconColor, size: 36),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.title,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count ${count == 1 ? "game" : "games"}',
                  style: const TextStyle(
                    color: AppColors.subtitle,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
