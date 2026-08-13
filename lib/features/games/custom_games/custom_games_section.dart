// "Your Goals" row on the dashboard. Tap a card to play, tap × to delete.
// Hidden when the user isn't signed in or has no games.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/hooks/hooks.dart';
import '../../../core/providers/user_data_manager.dart';
import '../../../core/theme/app_colors.dart';
import 'custom_game.dart';
import 'custom_game_player.dart';
import 'custom_games_repository.dart';

// Delete events are tracked here. Points/answers are tracked in CustomGamePlayer.
class CustomGamesSection extends StatelessWidget {
  const CustomGamesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.select<UserDataProvider, String>((p) => p.uid);
    if (uid.isEmpty) return const SizedBox.shrink(); // not signed in: hide

    return StreamBuilder<List<CustomGame>>(
      stream: CustomGamesRepository.instance.watch(uid),
      builder: (context, snapshot) {
        final games = snapshot.data ?? const <CustomGame>[];
        if (games.isEmpty) return const SizedBox.shrink(); // no games: hide

        return Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(count: games.length),
              const SizedBox(height: 12),
              SizedBox(
                height: 134,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: games.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _CustomGameTile(
                    game: games[index],
                    uid: uid,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// "Your Goals (N)" heading.
class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text(
              'Your Goals',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.title,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '($count)',
              style: const TextStyle(
                color: AppColors.subtitle,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// One game card. Tap to play, × or long-press to delete.
class _CustomGameTile extends StatelessWidget {
  final CustomGame game;
  final String uid;

  const _CustomGameTile({required this.game, required this.uid});

  @override
  Widget build(BuildContext context) {
    // Stack floats the × on top of the card. The × has its own tap area
    // so tapping it deletes rather than opening the game.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CustomGamePlayer(game: game),
              ),
            ),
            onLongPress: () => _showDeleteSheet(context), // long-press: delete

            borderRadius: BorderRadius.circular(16),
            child: Container(
          width: 150,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(game.iconData, color: AppColors.primary, size: 22),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${game.pointsReward} pts',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  game.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.title,
                    height: 1.25,
                  ),
                ),
              ),
              // Only shown after at least one completion.
              if (game.completedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Done ${game.completedCount}×',
                    style: const TextStyle(
                      color: AppColors.subtitle,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
          ),
        ),
        // Delete button floated just outside the top-right corner.
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.18),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _confirmDelete(context),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: const Icon(
                  Icons.close,
                  size: 14,
                  color: AppColors.subtitle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Bottom sheet shown on long-press, with a delete option.
  void _showDeleteSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Icon(game.iconData, color: AppColors.primary, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          game.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.title,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SheetButton(
                  icon: Icons.delete_outline,
                  label: 'Delete this goal',
                  destructive: true,
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _confirmDelete(context);
                  },
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  // Confirmation dialog before deleting. Earned points are kept.
  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Delete this goal?'),
        content: Text(
          'This removes "${game.title}" from your dashboard. Points you have already earned stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return; // they backed out

    try {
      await CustomGamesRepository.instance.delete(uid: uid, gameId: game.id);
      // Log the deletion for research (no personal info).
      // ignore: unawaited_futures
      TelemetryHooks.logEvent(
        'custom_game_deleted',
        parameters: {
          'gameId': game.id,
          'category': game.category.name,
          'completedCount': game.completedCount,
        },
        userId: uid,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }
}

// Row button used in the delete sheet. Red when destructive.
class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _SheetButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = destructive
        ? Colors.redAccent.withValues(alpha: 0.08)
        : Colors.white;
    final fg = destructive ? Colors.redAccent : AppColors.title;
    final borderColor = destructive
        ? Colors.redAccent.withValues(alpha: 0.4)
        : AppColors.cardBorder;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
