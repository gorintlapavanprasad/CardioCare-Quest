// Game Catalog - a grid of category tiles, one per health topic.
// Flat tiles instead of expandable sections (easier for older users).
// "Your Goals" tile appears only if the user has made custom games.
// The BP-logging game is reached from the dashboard, not here.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/user_data_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../games/custom_games/custom_game.dart';
import '../../games/custom_games/custom_games_repository.dart';
import '../../games/game_stories.dart';
import 'category_games_screen.dart';
import 'custom_games_screen.dart';

class GameCatalogScreen extends StatefulWidget {
  const GameCatalogScreen({super.key});

  @override
  State<GameCatalogScreen> createState() => _GameCatalogScreenState();
}

class _GameCatalogScreenState extends State<GameCatalogScreen> {
  // Category tiles, shuffled fresh each visit but stable during rebuilds.
  late final Map<GameCategory, List<GameStory>> _byCategory;
  late final List<GameCategory> _categories;

  // Remembers last visit's order so each new visit looks visibly different.
  static List<GameCategory>? _lastOrder;
  static final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _byCategory = GameCatalog.getCatalogGamesByCategory();
    _categories = _freshShuffledOrder(_byCategory.keys.toList());
    _lastOrder = List<GameCategory>.from(_categories);
  }

  // Shuffles categories, retrying until the order differs from last time.
  // Stops after 8 tries so a 1-item list doesn't loop forever.
  List<GameCategory> _freshShuffledOrder(List<GameCategory> cats) {
    if (cats.length < 2) return cats;
    final order = List<GameCategory>.from(cats);
    for (var attempt = 0; attempt < 8; attempt++) {
      order.shuffle(_rng);
      final prev = _lastOrder;
      // Accept the first order that isn't identical to last time's.
      if (prev == null || !_sameOrder(order, prev)) return order;
    }
    return order;
  }

  bool _sameOrder(List<GameCategory> a, List<GameCategory> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Builds a tile per category plus "Your Goals" when the user has custom games.
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
      // Watches custom games live; "Your Goals" tile appears once they've made one.
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

// Square tile: icon, label, game count. Whole tile is tappable; screen reader reads as one line.
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
