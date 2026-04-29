import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_game_host.dart';

/// Dog Walking quest screen. The whole game is a Twine HTML page in
/// `assets/game/dog_quest.html` plumbed through the generic
/// [TwineGameHost] — see `lib/core/widgets/twine_game_host.dart`.
///
/// To add a new movement-style game, just write the HTML and wrap it the
/// same way:
///
///   return TwineGameHost(
///     gameId: 'salt_sludge',
///     gameTitle: 'Salt Sludge',
///     htmlAsset: 'assets/game/salt_sludge.html',
///     targetDistance: targetDistance,
///   );
///
/// All the WebView wiring, GPS tracking, offline writes, watchdog Timer,
/// resume logic, race-safe end-game, telemetry, exit-confirmation, and
/// resume-state persistence are handled by the host.
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
