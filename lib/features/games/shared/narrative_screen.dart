import 'package:flutter/material.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';
import 'package:cardio_care_quest/features/games/game_stories.dart';

class NarrativeScreen extends StatelessWidget {
  final GameStory game;

  const NarrativeScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(game.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              game.narrative,
              style: const TextStyle(fontSize: 18, height: 1.5),
            ),
            const SizedBox(height: 32),
            const Text(
              'Why This Matters',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              game.medicalContext,
              style: const TextStyle(fontSize: 16, color: AppColors.subtitle),
            ),
            const SizedBox(height: 32),
            const Text(
              'Health Benefits',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...game.benefits.map(
              (benefit) => ListTile(
                leading: const Icon(Icons.check_circle, color: AppColors.success),
                title: Text(benefit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

