import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/widgets/twine_game_host.dart';

/// Salt Sludge — second movement quest, demonstrating that
/// [TwineGameHost] handles arbitrary Twine HTML pages with no per-game
/// engineering work beyond a thin wrapper. See
/// `lib/core/widgets/twine_game_host.dart` for everything that's handled
/// for free (GPS, OfflineQueue, watchdog, resume, race-safe end-game,
/// telemetry).
///
/// To add another movement game, copy this file, change the four
/// constructor arguments, drop a new HTML in `assets/game/`, register the
/// asset in `pubspec.yaml`, and add the route in
/// `game_catalog_screen.dart`.
class SaltSludgeGame extends StatelessWidget {
  final double targetDistance;

  const SaltSludgeGame({super.key, required this.targetDistance});

  @override
  Widget build(BuildContext context) {
    return TwineGameHost(
      gameId: 'salt_sludge',
      gameTitle: 'Salt Sludge',
      htmlAsset: 'assets/game/salt_sludge.html',
      targetDistance: targetDistance,
    );
  }
}
