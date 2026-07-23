import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_game_host.dart';

// Dog Walking - a real walking game. The game itself is an HTML page; this
// class loads it inside TwineGameHost, the heavier host that ALSO tracks
// your GPS walk. The host handles all the hard parts (GPS, saving,
// resuming, etc.) so this wrapper stays tiny.

// Shows the Dog Walking game. targetDistance is how far (in metres) to walk.
class DogQuestGame extends StatelessWidget {
  final double targetDistance;

  const DogQuestGame({super.key, required this.targetDistance});

  @override
  Widget build(BuildContext context) {
    // Load the HTML game in the GPS-tracking host and pass along the goal distance.
    return TwineGameHost(
      gameId: 'dog_quest',
      gameTitle: 'Dog Walking',
      htmlAsset: 'assets/game/dog_quest.html',
      targetDistance: targetDistance,
    );
  }
}
