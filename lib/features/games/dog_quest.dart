import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_game_host.dart';

// Loads the Dog Walking HTML game in TwineGameHost, which handles GPS tracking.
class DogQuestGame extends StatelessWidget {
  final double targetDistance;

  const DogQuestGame({super.key, required this.targetDistance});

  @override
  Widget build(BuildContext context) {
    return TwineGameHost(
      gameId: 'dog_quest',
      gameTitle: 'Dog Walking',
      htmlAsset: 'assets/game/dog_quest.html',
      targetDistance: targetDistance,
    );
  }
}
