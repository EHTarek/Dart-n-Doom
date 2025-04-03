import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../../home_page.dart';
import '../../core/util/platform_helper.dart';
import 'mobile_controls.dart';

class GameContainer extends StatelessWidget {
  final String username;
  final int difficulty;

  const GameContainer({
    Key? key,
    required this.username,
    required this.difficulty,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isMobile = PlatformHelper.shouldShowMobileControls(context);
    final game = DoomCloneGame(
        username: username, difficulty: difficulty, isMobile: isMobile);

    return Scaffold(
      body: Stack(
        children: [
          // The game itself
          GameWidget(game: game),

          // Mobile controls overlay (only shown on mobile)
          if (isMobile)
            MobileControls(
              onMove: (dx, dy) {
                // Call the game's movement method
                game.handleMobileMovement(dx, dy);
              },
              onAttack: () {
                // Call the game's attack method
                game.handleMobileAttack(true);
              },
              onAttackEnd: () {
                // End the attack
                game.handleMobileAttack(false);
              },
            ),
        ],
      ),
    );
  }
}
