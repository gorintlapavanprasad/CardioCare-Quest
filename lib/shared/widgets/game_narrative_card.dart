import 'package:flutter/material.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';
import 'package:cardio_care_quest/features/games/game_stories.dart';

class GameNarrativeCard extends StatelessWidget {
  final GameStory game;
  final VoidCallback? onPlayTap;

  const GameNarrativeCard({
    super.key,
    required this.game,
    this.onPlayTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color cardColor = Color(int.parse(game.color.replaceFirst('#', '0xFF')));

    return Material(
      child: InkWell(
        onTap: game.status == 'active'
            ? onPlayTap
            : () => _showNarrativeModal(context, cardColor),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: cardColor.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with icon and status badge
              Row(
                children: [
                  Text(game.emoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          game.title,
                          style: const TextStyle(
                            color: AppColors.title,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          game.shortDescription,
                          style: const TextStyle(
                            color: AppColors.subtitle,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (game.status == 'coming_soon')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                      color: AppColors.subtitle.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                        color: AppColors.subtitle.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Text(
                        'Coming Soon',
                        style: TextStyle(
                        color: AppColors.subtitle,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Narrative preview
              Text(
                game.narrative.trim().split('\n').first,
                style: const TextStyle(
                  color: AppColors.body,
                  fontSize: 13,
                  height: 1.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              // Benefits tags
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: game.benefits
                    .take(3)
                    .map(
                      (benefit) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cardColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          benefit,
                          style: TextStyle(
                            color: cardColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // High-fidelity narrative modal
  void _showNarrativeModal(BuildContext context, Color cardColor) {
    final Color surfaceColor = cardColor.withValues(alpha: 0.08);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                  color: AppColors.subtitle.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(game.emoji,
                                style: const TextStyle(fontSize: 44)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    game.title,
                                    style: const TextStyle(
                                      color: AppColors.title,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    game.shortDescription,
                                    style: const TextStyle(
                                      color: AppColors.subtitle,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Narrative section
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: cardColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            game.narrative.trim(),
                            style: const TextStyle(
                              color: AppColors.body,
                              fontSize: 15,
                              height: 1.8,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Medical context
                        Text(
                          'Why This Matters',
                          style: TextStyle(
                            color: AppColors.title,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.cardBorder,
                            ),
                          ),
                          child: Text(
                            game.medicalContext,
                            style: const TextStyle(
                              color: AppColors.subtitle,
                              fontSize: 13,
                              height: 1.7,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Benefits
                        Text(
                          'Health Benefits',
                          style: TextStyle(
                            color: AppColors.title,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...game.benefits.map((benefit) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                benefit,
                                style: const TextStyle(
                                  color: AppColors.body,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        )),
                        const SizedBox(height: 32),

                        // Status message
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                game.status == 'coming_soon'
                                    ? Icons.lock_clock_rounded
                                    : Icons.check_circle_rounded,
                                color: cardColor,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                game.status == 'coming_soon'
                                    ? 'This quest is coming soon'
                                    : 'This quest is ready',
                                style: TextStyle(
                                  color: cardColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
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

