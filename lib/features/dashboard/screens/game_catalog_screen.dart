// Game Catalog - a grid of category tiles (one per health topic).
// Tap a tile to see that category's games (CategoryGamesScreen).
//
// It used to be collapsible fold-out sections, but those were fiddly for
// older or shaky-handed users, so now it's plain flat tiles: tile ->
// list -> preview popup -> play. Simple straight line, no expanding.
//
// The person's own games show up as an extra "Your Goals" tile, but only
// when they've made some. The BP-logging game is left out on purpose
// (it's reached from the dashboard's blood-pressure card instead).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/user_data_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../games/custom_games/custom_game.dart';
import '../../games/custom_games/custom_games_repository.dart';
import '../../games/game_stories.dart';
import 'category_games_screen.dart';
import 'custom_games_screen.dart';

// The catalog screen: builds the tile grid and adds "Your Goals" if needed.
class GameCatalogScreen extends StatefulWidget {
  const GameCatalogScreen({super.key});

  @override
  State<GameCatalogScreen> createState() => _GameCatalogScreenState();
}

class _GameCatalogScreenState extends State<GameCatalogScreen> {
  // The five factor tiles, mapped to their games. We shuffle the order once
  // each time the screen opens so the tiles land in a fresh spot every visit,
  // but stay put during rebuilds (e.g. when "Your Goals" pops in).
  late final Map<GameCategory, List<GameStory>> _byCategory;
  late final List<GameCategory> _categories;

  @override
  void initState() {
    super.initState();
    _byCategory = GameCatalog.getCatalogGamesByCategory();
    _categories = _byCategory.keys.toList()..shuffle();
  }

  // Build a tile per category, plus a "Your Goals" tile once the user
  // has any custom games. We watch custom games live so that tile pops
  // in on its own.
  @override
  Widget build(BuildContext context) {
    final byCategory = _byCategory;
    final categories = _categories;
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
      // Watch the user's custom games. No "Your Goals" tile until they've
      // made at least one. Empty stream while the user id is still loading,
      // so the category tiles show right away and Goals pops in after.
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
                // Yellow + sparkle icon = "my own goals", the same look
                // used elsewhere so people recognise it.
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

// One square tile - icon, label, and game count. Used for both the
// category tiles and the "Your Goals" tile. The whole tile is tappable
// (easier for shaky hands), and a screen reader reads it as one line
// like "Exercise, 1 game" instead of three separate bits.
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
