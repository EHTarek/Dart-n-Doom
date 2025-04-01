import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';

// Simple enemy class
class Enemy {
  Offset position;
  double size;
  bool alive = true;
  Color color = Colors.red;
  bool hit = false; // Track if enemy was just hit
  double hitTime = 0; // Timer for hit animation
  int health = 100; // Enemy health
  bool isShooting = false; // Track if enemy is shooting
  double shootAnimTime = 0; // Timer for enemy shooting animation
  double shootCooldown = 0; // Cooldown timer between shots
  double moveSpeed = 20; // Movement speed
  bool isAggressive = false; // Whether enemy actively hunts player
  double lastSeenPlayerTime = 0; // Track when enemy last saw player
  Offset lastKnownPlayerPos = Offset.zero; // Last known player position

  Enemy(this.position, this.size, {this.color = Colors.red}) {
    // Randomize some enemy properties
    moveSpeed = 15 + Random().nextDouble() * 15; // Between 15-30
    isAggressive = Random().nextBool(); // 50% chance to be aggressive
  }

  // Check if enemy can see the player (for shooting)
  bool canSeePlayer(Offset playerPos, List<List<int>> map, double cellSize) {
    // Vector from enemy to player
    double dx = playerPos.dx - position.dx;
    double dy = playerPos.dy - position.dy;

    // Distance to player
    double distance = sqrt(dx * dx + dy * dy);

    // Too far to see
    if (distance > 500) return false;

    // Check if there's a wall between enemy and player
    double stepSize = 5;
    int steps = (distance / stepSize).floor();

    for (int i = 1; i < steps; i++) {
      // Position along the line from enemy to player
      double checkX = position.dx + dx * i / steps;
      double checkY = position.dy + dy * i / steps;

      // Map cell coordinates
      int mapX = (checkX / cellSize).floor();
      int mapY = (checkY / cellSize).floor();

      // Check if position is within map bounds
      if (mapX < 0 || mapX >= map[0].length || mapY < 0 || mapY >= map.length) {
        continue;
      }

      // Check if there's a wall at this position
      if (map[mapY][mapX] == 1) {
        return false; // Wall blocks sight
      }
    }

    // Enemy can see player, update last known position
    lastKnownPlayerPos = playerPos;
    lastSeenPlayerTime = 0;
    return true; // No walls blocking sight
  }

  // Move enemy towards target
  void moveTowards(
      Offset target, double dt, List<List<int>> map, double cellSize) {
    // Vector to target
    double dx = target.dx - position.dx;
    double dy = target.dy - position.dy;

    // Distance to target
    double distance = sqrt(dx * dx + dy * dy);

    // If we're very close to target, stop moving
    if (distance < 5) return;

    // Normalize direction
    dx = dx / distance;
    dy = dy / distance;

    // Calculate new position
    double newX = position.dx + dx * moveSpeed * dt;
    double newY = position.dy + dy * moveSpeed * dt;

    // Check for wall collision at new position
    int cellX = (newX / cellSize).floor();
    int cellY = (newY / cellSize).floor();

    // Skip movement if it would collide with a wall
    if (cellX >= 0 &&
        cellX < map[0].length &&
        cellY >= 0 &&
        cellY < map.length &&
        map[cellY][cellX] != 1) {
      position = Offset(newX, newY);
    }
  }
}

// Define item types
enum ItemType { healthPack, ammo }

// Item class for pickups
class Item {
  Offset position;
  ItemType type;
  bool active = true;
  double rotationAngle = 0; // For animation

  Item(this.position, this.type);
}

class HomePage extends StatelessWidget {
  final String username;
  final int difficulty;

  const HomePage({
    super.key,
    required this.username,
    required this.difficulty,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameWidget(
        game: DoomCloneGame(username: username, difficulty: difficulty),
      ),
    );
  }
}

class DoomCloneGame extends FlameGame with KeyboardEvents, TapDetector {
  final String username;
  final int difficulty;

  // Player stats
  int health = 100;
  int ammo = 50;
  bool isShooting = false; // Track if player is shooting for gun animation
  double shootAnimTime = 0; // Timer for shooting animation
  double shootCooldown = 0; // Cooldown between shots
  int score = 0; // Player score
  bool gameOver = false; // Track game state
  double damageIndicatorTime = 0; // For flashing screen when damaged
  double lastDamageAmount = 0; // Amount of last damage taken
  double moveSpeed = 100; // units per second

  // Wall texture
  ui.Image? brickTexture;
  bool textureLoaded = false;

  // Enemy texture
  ui.Image? enemyTexture;
  bool enemyTextureLoaded = false;

  // Gun texture
  ui.Image? gunTexture;
  bool gunTextureLoaded = false;

  // Items list
  List<Item> items = [];

  // Simple map: 1 = wall, 0 = empty space.
  final List<List<int>> map = [
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 1, 0, 1, 0, 1, 0, 0, 1],
    [1, 0, 1, 0, 1, 0, 1, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 1, 0, 1, 0, 1, 0, 0, 1],
    [1, 0, 1, 0, 1, 0, 1, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  ];
  final int mapWidth = 10;
  final int mapHeight = 10;
  final double cellSize = 64; // Each map cell size in world units

  // Player starting position and properties
  Offset playerPos = Offset(160, 160);
  double playerAngle = 0; // in radians
  double rotSpeed = pi / 2; // radians per second

  // Store keys currently pressed
  Set<LogicalKeyboardKey> keysPressed = {};

  // List of enemies
  List<Enemy> enemies = [];

  DoomCloneGame({
    required this.username,
    required this.difficulty,
  }) {
    // Adjust game difficulty based on the provided level
    if (difficulty == 0) {
      // Easy
      health = 150;
      ammo = 100;
      moveSpeed = 120;
    } else if (difficulty == 1) {
      // Medium
      health = 100;
      ammo = 50;
      moveSpeed = 100;
    } else if (difficulty == 2) {
      // Hard
      health = 75;
      ammo = 30;
      moveSpeed = 90;
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Generate brick texture
    brickTexture = await _generateBrickTexture();
    textureLoaded = true;

    // Load enemy texture from assets
    enemyTexture = await _loadEnemyTexture();
    enemyTextureLoaded = true;

    // Load gun texture from assets
    gunTexture = await _loadGunTexture();
    gunTextureLoaded = true;

    // Add a variety of enemies in different positions with different colors
    enemies.add(Enemy(const Offset(320, 320), 30, color: Colors.red));
    enemies.add(Enemy(const Offset(480, 480), 35, color: Colors.blue.shade800));
    enemies
        .add(Enemy(const Offset(300, 480), 40, color: Colors.green.shade800));
    enemies
        .add(Enemy(const Offset(420, 220), 25, color: Colors.purple.shade800));
    enemies
        .add(Enemy(const Offset(200, 400), 38, color: Colors.orange.shade800));

    // Spawn some initial items
    _spawnItems();
  }

  // Spawn items randomly in the map
  void _spawnItems() {
    final Random random = Random();

    // Add some health packs
    for (int i = 0; i < 3; i++) {
      _spawnItem(ItemType.healthPack, random);
    }

    // Add some ammo packs
    for (int i = 0; i < 5; i++) {
      _spawnItem(ItemType.ammo, random);
    }
  }

  // Spawn a single item at an empty location
  void _spawnItem(ItemType type, Random random) {
    int attempts = 0;
    while (attempts < 20) {
      // Limit attempts to prevent infinite loop
      int x = random.nextInt(mapWidth - 2) + 1; // Keep away from edges
      int y = random.nextInt(mapHeight - 2) + 1;

      // Only spawn in empty spaces
      if (map[y][x] == 0) {
        // Convert to world position (center of cell)
        double posX = (x + 0.5) * cellSize;
        double posY = (y + 0.5) * cellSize;

        // Add item
        items.add(Item(Offset(posX, posY), type));
        break;
      }
      attempts++;
    }
  }

  // Load enemy texture from asset
  Future<ui.Image> _loadEnemyTexture() async {
    final ByteData data = await rootBundle.load('assets/images/enemy.png');
    final Uint8List bytes = data.buffer.asUint8List();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo fi = await codec.getNextFrame();
    return fi.image;
  }

  // Load gun texture from asset
  Future<ui.Image> _loadGunTexture() async {
    final ByteData data = await rootBundle.load('assets/images/gun.png');
    final Uint8List bytes = data.buffer.asUint8List();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo fi = await codec.getNextFrame();
    return fi.image;
  }

  // Generate a brick wall texture
  Future<ui.Image> _generateBrickTexture() async {
    const int textureSize = 64;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    // Fill background with darker mortar color
    canvas.drawRect(
      Rect.fromLTWH(0, 0, textureSize.toDouble(), textureSize.toDouble()),
      Paint()..color = Colors.brown.shade600,
    );

    // Draw brick pattern
    final Paint brickPaint = Paint()..color = Colors.brown.shade800;

    // First row of bricks
    canvas.drawRect(Rect.fromLTWH(2, 2, 28, 14), brickPaint);
    canvas.drawRect(Rect.fromLTWH(34, 2, 28, 14), brickPaint);

    // Second row (offset)
    canvas.drawRect(Rect.fromLTWH(2, 20, 14, 14), brickPaint);
    canvas.drawRect(Rect.fromLTWH(20, 20, 28, 14), brickPaint);
    canvas.drawRect(Rect.fromLTWH(52, 20, 10, 14), brickPaint);

    // Third row
    canvas.drawRect(Rect.fromLTWH(2, 38, 28, 14), brickPaint);
    canvas.drawRect(Rect.fromLTWH(34, 38, 28, 14), brickPaint);

    // Fourth row (offset)
    canvas.drawRect(Rect.fromLTWH(2, 56, 14, 6), brickPaint);
    canvas.drawRect(Rect.fromLTWH(20, 56, 28, 6), brickPaint);
    canvas.drawRect(Rect.fromLTWH(52, 56, 10, 6), brickPaint);

    // Add some variations to the bricks
    final Paint detailPaint = Paint()..color = Colors.brown.shade700;
    final Random rng = Random(42);

    for (int i = 0; i < 100; i++) {
      final double x = rng.nextDouble() * textureSize;
      final double y = rng.nextDouble() * textureSize;
      final double size = 1 + rng.nextDouble() * 3;
      canvas.drawCircle(Offset(x, y), size, detailPaint);
    }

    final ui.Picture picture = recorder.endRecording();
    return picture.toImage(textureSize, textureSize);
  }

  @override
  void render(Canvas canvas) {
    final size = canvasSize;

    // Clear screen with a dark background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..color = Colors.grey[800]!,
    );

    // --- 3D Raycasting rendering ---
    int numRays = size.x.toInt();
    double fov = pi / 3; // 60° field of view

    // Store distances for sprite rendering
    List<double> zBuffer = List.filled(numRays, double.infinity);

    for (int x = 0; x < numRays; x++) {
      // Calculate the current ray's angle
      double rayAngle = (playerAngle - fov / 2) + (x / numRays) * fov;

      // Raycasting: increment along the ray until we hit a wall or max distance.
      double distance = 0;
      bool hitWall = false;
      double hitX =
          0; // X-coordinate where the wall was hit (for texture mapping)

      while (!hitWall && distance < 1000) {
        distance += 1;
        double rayX = playerPos.dx + cos(rayAngle) * distance;
        double rayY = playerPos.dy + sin(rayAngle) * distance;
        int mapX = (rayX / cellSize).toInt();
        int mapY = (rayY / cellSize).toInt();

        // If out of bounds, consider it a wall.
        if (mapX < 0 || mapX >= mapWidth || mapY < 0 || mapY >= mapHeight) {
          hitWall = true;
          distance = 1000;
        } else {
          if (map[mapY][mapX] == 1) {
            hitWall = true;

            // Calculate exact hit position for texture mapping
            // The fractional part of the position is the texture coordinate
            hitX = rayX % cellSize / cellSize;
            if (rayAngle > pi * 0.5 && rayAngle < pi * 1.5) {
              hitX = 1.0 - hitX; // Correct for walls facing south
            }

            if (rayAngle > 0 && rayAngle < pi) {
              hitX = 1.0 - hitX; // Correct for walls facing east/west
            }
          }
        }
      }

      // Correct the "fishbowl" distortion
      double correctedDistance = distance * cos(rayAngle - playerAngle);

      // Store in zbuffer for sprite rendering
      zBuffer[x] = correctedDistance;

      // Compute wall height (scaling factor chosen empirically)
      double wallHeight = (cellSize / correctedDistance) * 277;

      // Draw a vertical slice for this ray
      double lineTop = (size.y / 2) - (wallHeight / 2);

      if (textureLoaded && brickTexture != null && hitWall && distance < 1000) {
        // Calculate texture coordinates
        int texX = (hitX * 64).toInt() % 64; // 64 is texture width

        // Draw wall slice with texture
        final Rect destRect =
            Rect.fromLTWH(x.toDouble(), lineTop, 1, wallHeight);

        final Rect srcRect =
            Rect.fromLTWH(texX.toDouble(), 0, 1, 64 // texture height
                );

        // Apply shading based on distance
        final int shade = 255 - min(255, (correctedDistance * 2).toInt());
        final double shadeFactor = shade / 255;

        // Paint with appropriate shade
        final paint = Paint()
          ..colorFilter = ColorFilter.mode(
              Color.fromRGBO((shadeFactor * 255).toInt(),
                  (shadeFactor * 255).toInt(), (shadeFactor * 255).toInt(), 1),
              BlendMode.modulate);

        // Draw the textured wall slice
        canvas.drawImageRect(brickTexture!, srcRect, destRect, paint);
      } else {
        // Fallback to solid color walls if texture not loaded

        // Shade the wall based on distance (closer = brighter)
        int shade = 255 - min(255, (correctedDistance * 2).toInt());

        // Apply different colors for walls based on direction
        Color wallColor;
        if (rayAngle < pi * 0.25 || rayAngle > pi * 1.75) {
          // Red walls for north
          wallColor = Color.fromARGB(255, shade, shade * 2 ~/ 3, shade ~/ 2);
        } else if (rayAngle < pi * 0.75) {
          // Blue walls for east
          wallColor = Color.fromARGB(255, shade ~/ 2, shade * 2 ~/ 3, shade);
        } else if (rayAngle < pi * 1.25) {
          // Brown walls for south
          wallColor = Color.fromARGB(255, shade, shade * 3 ~/ 4, shade ~/ 2);
        } else {
          // Green walls for west
          wallColor = Color.fromARGB(255, shade ~/ 2, shade, shade ~/ 2);
        }

        canvas.drawLine(
          Offset(x.toDouble(), lineTop),
          Offset(x.toDouble(), lineTop + wallHeight),
          Paint()..color = wallColor,
        );
      }
    }

    // Draw enemies (sprites)
    _drawEnemies(canvas, size, zBuffer, fov);

    // Draw items
    _drawItems(canvas, size, zBuffer, fov);

    // --- Optional: Draw a minimap in the top left corner ---
    _drawMinimap(canvas);

    // Draw the player's face/HUD at the bottom
    _drawPlayerHUD(canvas, size);

    // Draw weapon
    _drawWeapon(canvas, size);

    // Draw crosshair in the center of the screen
    _drawCrosshair(canvas, size);

    // Draw damage indicator when hurt
    if (damageIndicatorTime > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()..color = Colors.red.withOpacity(damageIndicatorTime * 0.5),
      );
    }

    // If game over, draw overlay
    if (gameOver) {
      // Dark overlay
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()..color = Colors.black.withOpacity(0.7),
      );

      // Game over text
      final TextSpan gameOverSpan = TextSpan(
        text: 'GAME OVER',
        style: const TextStyle(
          color: Colors.red,
          fontSize: 48,
          fontWeight: FontWeight.bold,
        ),
      );

      final TextPainter gameOverPainter = TextPainter(
        text: gameOverSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      gameOverPainter.layout(minWidth: size.x);
      gameOverPainter.paint(canvas, Offset(0, size.y / 2 - 70));

      // Score text
      final TextSpan scoreSpan = TextSpan(
        text: 'SCORE: $score',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      );

      final TextPainter scorePainter = TextPainter(
        text: scoreSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      scorePainter.layout(minWidth: size.x);
      scorePainter.paint(canvas, Offset(0, size.y / 2));

      // Restart instructions
      final TextSpan restartSpan = TextSpan(
        text: 'Press SPACE to restart',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      );

      final TextPainter restartPainter = TextPainter(
        text: restartSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      restartPainter.layout(minWidth: size.x);
      restartPainter.paint(canvas, Offset(0, size.y / 2 + 50));
    }
  }

  // Draw enemies as sprites in the 3D view
  void _drawEnemies(
      Canvas canvas, Vector2 size, List<double> zBuffer, double fov) {
    for (Enemy enemy in enemies) {
      if (!enemy.alive) continue;

      // Vector from player to enemy
      double dx = enemy.position.dx - playerPos.dx;
      double dy = enemy.position.dy - playerPos.dy;

      // Distance to enemy
      double distance = sqrt(dx * dx + dy * dy);

      // Angle between player and enemy
      double angle = atan2(dy, dx) - playerAngle;

      // Normalize angle
      while (angle > pi) angle -= 2 * pi;
      while (angle < -pi) angle += 2 * pi;

      // Check if enemy is in field of view (with some buffer)
      if (angle.abs() > fov / 2 + 0.2) continue;

      // Calculate screen position
      double screenX = (size.x / 2) + tan(angle) * (size.x / 2);

      // Calculate sprite height based on distance
      double spriteHeight = size.y / distance * enemy.size;

      // Only render if in front of a wall
      if (screenX >= 0 && screenX < size.x) {
        int screenXInt = screenX.toInt();
        if (distance < zBuffer[screenXInt]) {
          // Determine sprite width based on height (keep ratio)
          double spriteWidth = spriteHeight * 0.6;

          // Calculate top position of sprite
          double spriteTop = size.y / 2 - spriteHeight / 2;

          // Create rectangle for enemy
          final enemyRect = Rect.fromLTWH(
            screenX - spriteWidth / 2,
            spriteTop,
            spriteWidth,
            spriteHeight,
          );

          if (enemyTextureLoaded && enemyTexture != null) {
            // Draw enemy using the loaded image
            final paint = Paint();

            // If enemy is hit, tint the sprite red
            if (enemy.hit) {
              paint.colorFilter = ColorFilter.mode(
                Colors.red,
                BlendMode.srcATop,
              );
            }

            // Apply distance-based darkening
            final int shade = 255 - min(255, (distance * 0.5).toInt());
            final double shadeFactor = shade / 255;

            // Combine hit effect with distance shading if needed
            if (!enemy.hit) {
              paint.colorFilter = ColorFilter.mode(
                  Color.fromRGBO(
                      (shadeFactor * 255).toInt(),
                      (shadeFactor * 255).toInt(),
                      (shadeFactor * 255).toInt(),
                      1),
                  BlendMode.modulate);
            }

            // Draw the image
            canvas.drawImageRect(
              enemyTexture!,
              Rect.fromLTWH(0, 0, enemyTexture!.width.toDouble(),
                  enemyTexture!.height.toDouble()),
              enemyRect,
              paint,
            );
          } else {
            // Fallback to drawing soldier if texture isn't loaded
            _drawSoldierEnemy(canvas, enemyRect, enemy, distance);
          }

          // Draw health bar above enemy
          _drawEnemyHealthBar(
              canvas,
              enemy,
              Offset(screenX - spriteWidth / 2,
                  spriteTop - 10 - (spriteHeight * 0.05) // Position above enemy
                  ),
              spriteWidth);

          // Draw muzzle flash if enemy is shooting
          if (enemy.isShooting && enemy.shootAnimTime < 0.2) {
            final flashPaint = Paint()..color = Colors.orange;
            final innerFlashPaint = Paint()..color = Colors.yellow;

            // Position muzzle flash at the end of the rifle
            double flashX =
                screenX + spriteWidth * 0.3; // Adjust based on your enemy image
            double flashY = spriteTop +
                spriteHeight * 0.4; // Adjust based on your enemy image

            canvas.drawCircle(
                Offset(flashX, flashY), spriteWidth * 0.1, flashPaint);

            canvas.drawCircle(
                Offset(flashX, flashY), spriteWidth * 0.05, innerFlashPaint);
          }
        }
      }
    }
  }

  // Draw a realistic soldier-like enemy
  void _drawSoldierEnemy(
      Canvas canvas, Rect rect, Enemy enemy, double distance) {
    // Base colors
    final Color uniformColor = enemy.hit ? Colors.red : Colors.green.shade900;
    final Color helmetColor = Colors.green.shade800;
    final Color skinColor = Colors.brown.shade200;
    final Color equipmentColor = Colors.grey.shade700;

    final double centerX = rect.left + rect.width / 2;
    final double width = rect.width;
    final double height = rect.height;

    // Draw body (torso)
    final bodyRect = Rect.fromLTWH(
        rect.left,
        rect.top + height * 0.25, // Start below head
        width,
        height * 0.5 // Body is about half the sprite height
        );

    canvas.drawRect(bodyRect, Paint()..color = uniformColor);

    // Draw legs
    final leftLegRect = Rect.fromLTWH(rect.left + width * 0.15,
        rect.top + height * 0.75, width * 0.3, height * 0.25);

    final rightLegRect = Rect.fromLTWH(rect.left + width * 0.55,
        rect.top + height * 0.75, width * 0.3, height * 0.25);

    canvas.drawRect(leftLegRect, Paint()..color = uniformColor);
    canvas.drawRect(rightLegRect, Paint()..color = uniformColor);

    // Draw arms
    // Left arm
    final leftArmRect = Rect.fromLTWH(
        rect.left, rect.top + height * 0.3, width * 0.15, height * 0.4);

    // Right arm (holding gun)
    final rightArmRect = Rect.fromLTWH(rect.left + width * 0.85,
        rect.top + height * 0.3, width * 0.15, height * 0.4);

    canvas.drawRect(leftArmRect, Paint()..color = uniformColor);
    canvas.drawRect(rightArmRect, Paint()..color = uniformColor);

    // Draw head (with helmet)
    final headRect = Rect.fromLTWH(rect.left + width * 0.25,
        rect.top + height * 0.05, width * 0.5, height * 0.2);

    // Helmet (slightly larger than head)
    final helmetRect = Rect.fromLTWH(
        headRect.left - width * 0.05,
        headRect.top - width * 0.05,
        headRect.width + width * 0.1,
        headRect.height + width * 0.05);

    canvas.drawRRect(
        RRect.fromRectAndRadius(helmetRect, Radius.circular(width * 0.1)),
        Paint()..color = helmetColor);

    // Face
    canvas.drawOval(headRect, Paint()..color = skinColor);

    // Eyes
    final eyeSize = width * 0.08;
    final eyeY = headRect.top + headRect.height * 0.4;

    // Left eye
    canvas.drawCircle(Offset(headRect.left + headRect.width * 0.3, eyeY),
        eyeSize / 2, Paint()..color = Colors.black);

    // Right eye
    canvas.drawCircle(Offset(headRect.left + headRect.width * 0.7, eyeY),
        eyeSize / 2, Paint()..color = Colors.black);

    // Draw rifle
    final rifleWidth = width * 0.8;
    final rifleHeight = height * 0.1;

    final riflePath = Path();
    // Main rifle body
    riflePath.addRect(Rect.fromLTWH(
        rect.left + width * 0.2,
        rect.top + height * 0.4, // At arm height
        rifleWidth,
        rifleHeight));

    // Rifle handle
    riflePath.addRect(Rect.fromLTWH(rect.left + width * 0.3,
        rect.top + height * 0.4 + rifleHeight, width * 0.15, height * 0.1));

    canvas.drawPath(riflePath, Paint()..color = equipmentColor);

    // Draw tactical vest
    final vestPath = Path();
    vestPath.addRect(Rect.fromLTWH(bodyRect.left + bodyRect.width * 0.1,
        bodyRect.top, bodyRect.width * 0.8, bodyRect.height * 0.6));

    // Draw with darker color and stroke
    canvas.drawPath(
        vestPath,
        Paint()
          ..color = Colors.brown.shade700
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 0.05);

    // Add equipment pouches on vest
    for (int i = 0; i < 2; i++) {
      canvas.drawRect(
          Rect.fromLTWH(
              bodyRect.left + bodyRect.width * (0.2 + i * 0.4),
              bodyRect.top + bodyRect.height * 0.1,
              bodyRect.width * 0.2,
              bodyRect.height * 0.2),
          Paint()..color = equipmentColor);
    }
  }

  void _drawMinimap(Canvas canvas) {
    // Make minimap larger and more visible
    double scale = 0.3;
    double mapDisplayWidth = mapWidth * cellSize * scale;
    double mapDisplayHeight = mapHeight * cellSize * scale;

    // Draw a dark background for the minimap
    canvas.drawRect(
      Rect.fromLTWH(0, 0, mapDisplayWidth + 10, mapDisplayHeight + 10),
      Paint()..color = Colors.black.withOpacity(0.7),
    );

    // Draw the map grid
    for (int y = 0; y < mapHeight; y++) {
      for (int x = 0; x < mapWidth; x++) {
        // Choose colors for walls vs empty spaces
        Color cellColor = map[y][x] == 1
            ? Colors.grey.shade300 // Walls are light
            : Colors.grey.shade900; // Empty spaces are dark

        // Draw cell with a slight border
        canvas.drawRect(
          Rect.fromLTWH(5 + x * cellSize * scale, 5 + y * cellSize * scale,
              cellSize * scale - 1, cellSize * scale - 1),
          Paint()..color = cellColor,
        );
      }
    }

    // Draw player on the minimap
    double px = 5 + playerPos.dx * scale;
    double py = 5 + playerPos.dy * scale;

    // Draw field of view
    final fovPath = Path();
    double fov = pi / 3; // Match the game's FOV
    fovPath.moveTo(px, py);
    fovPath.lineTo(px + cos(playerAngle - fov / 2) * mapDisplayWidth,
        py + sin(playerAngle - fov / 2) * mapDisplayWidth);
    fovPath.lineTo(px + cos(playerAngle + fov / 2) * mapDisplayWidth,
        py + sin(playerAngle + fov / 2) * mapDisplayWidth);
    fovPath.close();

    canvas.drawPath(
        fovPath,
        Paint()
          ..color = Colors.yellow.withOpacity(0.2)
          ..style = PaintingStyle.fill);

    // Draw player position (red dot)
    canvas.drawCircle(Offset(px, py), 6, Paint()..color = Colors.red);

    // Draw player direction (triangle)
    final directionPath = Path();
    directionPath.moveTo(
        px + cos(playerAngle) * 12, py + sin(playerAngle) * 12);
    directionPath.lineTo(
        px + cos(playerAngle + 2.5) * 8, py + sin(playerAngle + 2.5) * 8);
    directionPath.lineTo(
        px + cos(playerAngle - 2.5) * 8, py + sin(playerAngle - 2.5) * 8);
    directionPath.close();

    canvas.drawPath(directionPath, Paint()..color = Colors.red.shade700);

    // Draw enemies on minimap
    for (Enemy enemy in enemies) {
      if (!enemy.alive) continue;

      double ex = 5 + enemy.position.dx * scale;
      double ey = 5 + enemy.position.dy * scale;

      // Enemy color based on health
      Color enemyColor = enemy.health > 60
          ? Colors.green
          : enemy.health > 30
              ? Colors.orange
              : Colors.red;

      // Draw enemy dot
      canvas.drawCircle(Offset(ex, ey), 4, Paint()..color = enemyColor);

      // Draw outline
      canvas.drawCircle(
          Offset(ex, ey),
          5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }

    // Draw map border
    canvas.drawRect(
      Rect.fromLTWH(0, 0, mapDisplayWidth + 10, mapDisplayHeight + 10),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Draw "MAP" label
    final mapLabel = TextSpan(
      text: 'MAP',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );

    final labelPainter = TextPainter(
      text: mapLabel,
      textDirection: TextDirection.ltr,
    );

    labelPainter.layout();
    labelPainter.paint(
        canvas,
        Offset((mapDisplayWidth + 10) / 2 - labelPainter.width / 2,
            mapDisplayHeight + 12));

    // Draw enemy count label
    int aliveEnemies = enemies.where((e) => e.alive).length;
    final enemyCountLabel = TextSpan(
      text: 'ENEMIES: $aliveEnemies',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );

    final enemyLabelPainter = TextPainter(
      text: enemyCountLabel,
      textDirection: TextDirection.ltr,
    );

    enemyLabelPainter.layout();
    enemyLabelPainter.paint(
        canvas,
        Offset((mapDisplayWidth + 10) / 2 - enemyLabelPainter.width / 2,
            mapDisplayHeight + 28));
  }

  // Draw the player's face and HUD information
  void _drawPlayerHUD(Canvas canvas, Vector2 size) {
    // Background for the HUD
    canvas.drawRect(
      Rect.fromLTWH(0, size.y - 80, size.x, 80),
      Paint()..color = Colors.black,
    );

    // Draw player's face
    final faceRect = Rect.fromLTWH(size.x / 2 - 30, size.y - 70, 60, 60);

    // Face background
    canvas.drawOval(
      faceRect,
      Paint()..color = Colors.yellow.shade800,
    );

    // Eyes
    double eyeSize = 10;
    double eyeY = size.y - 50;

    // Left eye
    canvas.drawOval(
      Rect.fromLTWH(size.x / 2 - 18, eyeY, eyeSize, eyeSize),
      Paint()..color = Colors.white,
    );

    // Right eye
    canvas.drawOval(
      Rect.fromLTWH(size.x / 2 + 8, eyeY, eyeSize, eyeSize),
      Paint()..color = Colors.white,
    );

    // Pupils - follow pointer direction slightly
    canvas.drawCircle(
      Offset(size.x / 2 - 13 + cos(playerAngle) * 2,
          eyeY + 5 + sin(playerAngle) * 2),
      3,
      Paint()..color = Colors.black,
    );

    canvas.drawCircle(
      Offset(size.x / 2 + 13 + cos(playerAngle) * 2,
          eyeY + 5 + sin(playerAngle) * 2),
      3,
      Paint()..color = Colors.black,
    );

    // Mouth - changes with health
    final mouthPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Mouth shape depends on health
    if (health > 70) {
      // Happy mouth
      canvas.drawArc(
        Rect.fromLTWH(size.x / 2 - 15, size.y - 40, 30, 20),
        0,
        pi,
        false,
        mouthPaint,
      );
    } else if (health > 30) {
      // Neutral mouth
      canvas.drawLine(
        Offset(size.x / 2 - 15, size.y - 30),
        Offset(size.x / 2 + 15, size.y - 30),
        mouthPaint,
      );
    } else {
      // Sad mouth
      canvas.drawArc(
        Rect.fromLTWH(size.x / 2 - 15, size.y - 30, 30, 20),
        pi,
        pi,
        false,
        mouthPaint,
      );
    }

    // Health bar
    final healthBarWidth = 120.0;
    final healthWidth =
        (healthBarWidth * health / 100).clamp(0.0, healthBarWidth);

    // Health bar background
    canvas.drawRect(
      Rect.fromLTWH(10, size.y - 70, healthBarWidth, 15),
      Paint()..color = Colors.grey.shade800,
    );

    // Health bar fill
    canvas.drawRect(
      Rect.fromLTWH(10, size.y - 70, healthWidth, 15),
      Paint()..color = health > 30 ? Colors.green : Colors.red,
    );

    // Health text
    final healthTextSpan = TextSpan(
      text: 'HEALTH: $health%',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );

    final healthTextPainter = TextPainter(
      text: healthTextSpan,
      textDirection: TextDirection.ltr,
    );

    healthTextPainter.layout();
    healthTextPainter.paint(canvas, Offset(15, size.y - 68));

    // Ammo counter
    final ammoTextSpan = TextSpan(
      text: 'AMMO: $ammo',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );

    final ammoTextPainter = TextPainter(
      text: ammoTextSpan,
      textDirection: TextDirection.ltr,
    );

    ammoTextPainter.layout();
    ammoTextPainter.paint(canvas, Offset(size.x - 80, size.y - 68));
  }

  @override
  void update(double dt) {
    // Skip updates if game over
    if (gameOver) {
      // Only check for restart input
      if (keysPressed.contains(LogicalKeyboardKey.space)) {
        _restartGame();
      }
      return;
    }

    // Process input for player movement.
    if (keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW)) {
      playerPos = Offset(
        playerPos.dx + cos(playerAngle) * moveSpeed * dt,
        playerPos.dy + sin(playerAngle) * moveSpeed * dt,
      );
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
        keysPressed.contains(LogicalKeyboardKey.keyS)) {
      playerPos = Offset(
        playerPos.dx - cos(playerAngle) * moveSpeed * dt,
        playerPos.dy - sin(playerAngle) * moveSpeed * dt,
      );
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA)) {
      playerAngle -= rotSpeed * dt;
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD)) {
      playerAngle += rotSpeed * dt;
    }

    // Update shooting cooldown
    if (shootCooldown > 0) {
      shootCooldown -= dt;
    }

    // Update shooting animation
    if (isShooting) {
      shootAnimTime += dt;
      if (shootAnimTime > 0.3) {
        // Animation lasts for 0.3 seconds
        isShooting = false;
        shootAnimTime = 0;
      }
    }

    // Update damage indicator
    if (damageIndicatorTime > 0) {
      damageIndicatorTime -= dt;
    }

    // Update items
    _updateItems(dt);

    // Check for item pickups
    _checkItemPickups();

    // Update enemies
    _updateEnemies(dt);

    // Check for collisions with walls
    checkCollision();

    // Check for collisions with enemies
    checkEnemyCollisions();

    // Check if player is dead
    if (health <= 0 && !gameOver) {
      gameOver = true;
    }
  }

  // Update all items
  void _updateItems(double dt) {
    // Animate items (rotation/floating)
    for (Item item in items) {
      item.rotationAngle += dt * 2; // Rotate 2 radians per second
      if (item.rotationAngle > 2 * pi) {
        item.rotationAngle -= 2 * pi;
      }
    }
  }

  // Check if player has picked up items
  void _checkItemPickups() {
    double pickupDistance = 40; // Distance to pick up items

    for (int i = 0; i < items.length; i++) {
      if (!items[i].active) continue;

      double dx = items[i].position.dx - playerPos.dx;
      double dy = items[i].position.dy - playerPos.dy;
      double distance = sqrt(dx * dx + dy * dy);

      if (distance < pickupDistance) {
        // Apply item effect
        if (items[i].type == ItemType.healthPack) {
          health = min(100, health + 25); // Heal 25 HP
        } else if (items[i].type == ItemType.ammo) {
          ammo += 15; // Add 15 ammo
        }

        // Remove item
        items[i].active = false;
        items.removeAt(i);
        i--;

        // Maybe spawn a new item somewhere else
        if (Random().nextDouble() < 0.7) {
          // 70% chance
          _spawnItem(Random().nextBool() ? ItemType.healthPack : ItemType.ammo,
              Random());
        }
      }
    }
  }

  // Update all enemies
  void _updateEnemies(double dt) {
    for (int i = 0; i < enemies.length; i++) {
      Enemy enemy = enemies[i];

      // Skip dead enemies
      if (!enemy.alive) {
        enemy.hitTime += dt;
        if (enemy.hitTime > 1.0) {
          // Remove dead enemy after 1 second
          enemies.removeAt(i);
          i--;
        }
        continue;
      }

      // Increment last seen player time
      enemy.lastSeenPlayerTime += dt;

      // Handle enemy hit animation
      if (enemy.hit) {
        enemy.hitTime += dt;
        if (enemy.hitTime > 0.3) {
          // Hit animation ends
          enemy.hit = false;
          enemy.hitTime = 0;
        }
      }

      // Handle enemy shooting animation
      if (enemy.isShooting) {
        enemy.shootAnimTime += dt;
        if (enemy.shootAnimTime > 0.5) {
          enemy.isShooting = false;
          enemy.shootAnimTime = 0;
        }
      }

      // Handle enemy shooting cooldown
      if (enemy.shootCooldown > 0) {
        enemy.shootCooldown -= dt;
      }

      // Enemy AI
      bool canSee = enemy.canSeePlayer(playerPos, map, cellSize);

      // Check if enemy can shoot or move
      if (canSee) {
        // Enemy can see player
        if (enemy.shootCooldown <= 0) {
          // Try to shoot
          _enemyShoot(enemy);
        }
      } else if (enemy.isAggressive && enemy.lastSeenPlayerTime < 5.0) {
        // Aggressive enemy who lost sight of player recently will hunt
        enemy.moveTowards(enemy.lastKnownPlayerPos, dt, map, cellSize);
      } else if (Random().nextDouble() < 0.01) {
        // Random movement occasionally
        double randomAngle = Random().nextDouble() * 2 * pi;
        double moveDistance = 30; // How far to move

        Offset target = Offset(
            enemy.position.dx + cos(randomAngle) * moveDistance,
            enemy.position.dy + sin(randomAngle) * moveDistance);

        enemy.moveTowards(target, dt, map, cellSize);
      }
    }

    // Spawn new enemies if few remain
    if (enemies.length < 3 && Random().nextDouble() < 0.005) {
      _spawnNewEnemy();
    }
  }

  // Spawn a new enemy at a random location
  void _spawnNewEnemy() {
    final Random random = Random();
    int attempts = 0;

    while (attempts < 20) {
      int x = random.nextInt(mapWidth - 2) + 1;
      int y = random.nextInt(mapHeight - 2) + 1;

      // Only spawn in empty spaces and not too close to player
      if (map[y][x] == 0) {
        Offset pos = Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize);

        // Check distance to player
        double dx = pos.dx - playerPos.dx;
        double dy = pos.dy - playerPos.dy;
        double distanceToPlayer = sqrt(dx * dx + dy * dy);

        if (distanceToPlayer > 200) {
          // Not too close to player
          // Create enemy with random color
          Color color = Colors
              .primaries[random.nextInt(Colors.primaries.length)]
              .withOpacity(0.8);

          enemies.add(Enemy(pos, 30 + random.nextDouble() * 15, color: color));
          break;
        }
      }
      attempts++;
    }
  }

  // Enemy shoots at player
  void _enemyShoot(Enemy enemy) {
    // Start shooting animation
    enemy.isShooting = true;
    enemy.shootAnimTime = 0;
    enemy.shootCooldown =
        1.0 + Random().nextDouble() * 2.0; // 1-3 second cooldown

    // Vector from enemy to player
    double dx = playerPos.dx - enemy.position.dx;
    double dy = playerPos.dy - enemy.position.dy;
    double distance = sqrt(dx * dx + dy * dy);

    // Base hit chance depends on distance
    double hitChance = 1.0 - (distance / 500); // 100% at 0 distance, 0% at 500+
    hitChance = hitChance.clamp(0.2, 0.9); // Min 20%, max 90% hit chance

    // Check if enemy hits the player
    if (Random().nextDouble() < hitChance) {
      // Player is hit, reduce health
      // Damage increases the closer the enemy is
      int baseDamage = 10;
      double distanceFactor = 1.0 - (distance / 500).clamp(0.0, 0.8);
      int damageBoost =
          (distanceFactor * 15).round(); // Up to +15 damage at close range

      int damage = baseDamage +
          damageBoost +
          Random().nextInt(5); // 10-30 damage per hit

      // Apply damage
      health = max(0, health - damage);

      // Set damage indicator
      damageIndicatorTime = 0.5; // Show damage indicator for 0.5 seconds
      lastDamageAmount = damage.toDouble();

      // Screen shake could be added here
    }
  }

  // Restart the game
  void _restartGame() {
    // Reset player state
    health = 100;
    ammo = 50;
    playerPos = Offset(160, 160);
    playerAngle = 0;
    score = 0;
    gameOver = false;

    // Clear and respawn enemies
    enemies.clear();
    enemies.add(Enemy(const Offset(320, 320), 30, color: Colors.red));
    enemies.add(Enemy(const Offset(480, 480), 35, color: Colors.blue.shade800));
    enemies
        .add(Enemy(const Offset(300, 480), 40, color: Colors.green.shade800));
    enemies
        .add(Enemy(const Offset(420, 220), 25, color: Colors.purple.shade800));
    enemies
        .add(Enemy(const Offset(200, 400), 38, color: Colors.orange.shade800));

    // Reset items
    items.clear();
    _spawnItems();
  }

  // Add a muzzle flash effect
  void _drawWeapon(Canvas canvas, Vector2 size) {
    // Gun position at bottom center
    double gunWidth = size.x * 0.6;
    double gunHeight = size.y * 0.4;
    double gunX = (size.x - gunWidth) / 2;
    double gunY = size.y - gunHeight;

    // Recoil animation when shooting
    double recoilOffset = 0;
    if (isShooting) {
      // Move gun up during first half of animation, then back down
      if (shootAnimTime < 0.15) {
        recoilOffset = -shootAnimTime * 40; // Move up
      } else {
        recoilOffset = -(0.3 - shootAnimTime) * 40; // Move back down
      }
    }

    if (gunTextureLoaded && gunTexture != null) {
      // Draw gun using the loaded image
      final Rect destRect =
          Rect.fromLTWH(gunX, gunY + recoilOffset, gunWidth, gunHeight);

      final Rect srcRect = Rect.fromLTWH(
          0, 0, gunTexture!.width.toDouble(), gunTexture!.height.toDouble());

      // Draw the gun image
      canvas.drawImageRect(gunTexture!, srcRect, destRect, Paint());
    } else {
      // Fallback to simple pistol representation
      final Paint gunPaint = Paint()..color = Colors.grey;
      final Paint barrelPaint = Paint()..color = Colors.grey[700]!;

      // Draw gun body with recoil
      canvas.drawRect(
        Rect.fromLTWH(gunX, gunY + gunHeight * 0.6 + recoilOffset, gunWidth,
            gunHeight * 0.4),
        gunPaint,
      );

      // Draw gun barrel with recoil
      canvas.drawRect(
        Rect.fromLTWH(
            gunX + gunWidth * 0.4,
            gunY + gunHeight * 0.5 + recoilOffset,
            gunWidth * 0.2,
            gunHeight * 0.5),
        barrelPaint,
      );
    }

    // Draw muzzle flash when shooting
    if (isShooting && shootAnimTime < 0.15) {
      // Only show muzzle flash for first half of animation
      Paint flashPaint = Paint()..color = Colors.orange;
      double flashSize = 30 *
          (1 -
              shootAnimTime /
                  0.15); // Flash gets smaller as animation progresses

      // Calculate muzzle flash position based on gun image
      double flashX = size.x / 2;
      double flashY = gunTextureLoaded
          ? gunY + gunHeight * 0.3 + recoilOffset
          : gunY + gunHeight * 0.5 + recoilOffset - 10;

      // Draw muzzle flash
      canvas.drawCircle(
        Offset(flashX, flashY),
        flashSize,
        flashPaint,
      );

      // Add inner glow
      canvas.drawCircle(
        Offset(flashX, flashY),
        flashSize * 0.6,
        Paint()..color = Colors.yellow,
      );
    }
  }

  // Draw items in 3D view
  void _drawItems(
      Canvas canvas, Vector2 size, List<double> zBuffer, double fov) {
    for (Item item in items) {
      if (!item.active) continue;

      // Vector from player to item
      double dx = item.position.dx - playerPos.dx;
      double dy = item.position.dy - playerPos.dy;

      // Distance to item
      double distance = sqrt(dx * dx + dy * dy);

      // Angle between player and item
      double angle = atan2(dy, dx) - playerAngle;

      // Normalize angle
      while (angle > pi) angle -= 2 * pi;
      while (angle < -pi) angle += 2 * pi;

      // Check if item is in field of view
      if (angle.abs() > fov / 2 + 0.2) continue;

      // Calculate screen position
      double screenX = (size.x / 2) + tan(angle) * (size.x / 2);

      // Skip if outside screen
      if (screenX < 0 || screenX >= size.x) continue;

      // Only render if in front of a wall
      int screenXInt = screenX.toInt();
      if (screenXInt >= 0 &&
          screenXInt < zBuffer.length &&
          distance < zBuffer[screenXInt]) {
        // Calculate sprite size based on distance
        double itemSize = 20; // Base size
        double spriteHeight = size.y / distance * itemSize;
        double spriteWidth = spriteHeight;

        // Calculate top position
        double spriteTop = size.y / 2 - spriteHeight / 2;

        // Create item rectangle
        final itemRect = Rect.fromLTWH(
          screenX - spriteWidth / 2,
          spriteTop + sin(item.rotationAngle) * 5, // Floating animation
          spriteWidth,
          spriteHeight,
        );

        // Draw different items
        if (item.type == ItemType.healthPack) {
          // Draw health pack (white cross on red background)
          canvas.drawRect(itemRect, Paint()..color = Colors.red);

          // Draw cross
          final crossPaint = Paint()
            ..color = Colors.white
            ..strokeWidth = spriteWidth * 0.2;

          // Horizontal line
          canvas.drawLine(
            Offset(itemRect.left + itemRect.width * 0.2,
                itemRect.top + itemRect.height * 0.5),
            Offset(itemRect.right - itemRect.width * 0.2,
                itemRect.top + itemRect.height * 0.5),
            crossPaint,
          );

          // Vertical line
          canvas.drawLine(
            Offset(itemRect.left + itemRect.width * 0.5,
                itemRect.top + itemRect.height * 0.2),
            Offset(itemRect.left + itemRect.width * 0.5,
                itemRect.bottom - itemRect.height * 0.2),
            crossPaint,
          );
        } else if (item.type == ItemType.ammo) {
          // Draw ammo box (yellow box)
          canvas.drawRect(itemRect, Paint()..color = Colors.amber);

          // Draw bullets
          canvas.drawRect(
            Rect.fromLTWH(
              itemRect.left + itemRect.width * 0.2,
              itemRect.top + itemRect.height * 0.3,
              itemRect.width * 0.6,
              itemRect.height * 0.1,
            ),
            Paint()..color = Colors.black,
          );

          canvas.drawRect(
            Rect.fromLTWH(
              itemRect.left + itemRect.width * 0.2,
              itemRect.top + itemRect.height * 0.5,
              itemRect.width * 0.6,
              itemRect.height * 0.1,
            ),
            Paint()..color = Colors.black,
          );

          canvas.drawRect(
            Rect.fromLTWH(
              itemRect.left + itemRect.width * 0.2,
              itemRect.top + itemRect.height * 0.7,
              itemRect.width * 0.6,
              itemRect.height * 0.1,
            ),
            Paint()..color = Colors.black,
          );
        }
      }
    }
  }

  // Draw a crosshair in the center of the screen
  void _drawCrosshair(Canvas canvas, Vector2 size) {
    final centerX = size.x / 2;
    final centerY = size.y / 2;

    // Configure crosshair style
    final crosshairPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;

    final crosshairSize = 10.0; // Size of the crosshair

    // Draw crosshair lines
    // Horizontal line
    canvas.drawLine(
      Offset(centerX - crosshairSize, centerY),
      Offset(centerX + crosshairSize, centerY),
      crosshairPaint,
    );

    // Vertical line
    canvas.drawLine(
      Offset(centerX, centerY - crosshairSize),
      Offset(centerX, centerY + crosshairSize),
      crosshairPaint,
    );

    // Draw a small circle in the center (optional)
    canvas.drawCircle(
      Offset(centerX, centerY),
      2,
      crosshairPaint,
    );
  }

  // Draw enemy health bar
  void _drawEnemyHealthBar(
      Canvas canvas, Enemy enemy, Offset position, double width) {
    final healthPct = enemy.health / 100.0;
    final height = width * 0.05; // Height proportional to width

    // Background
    canvas.drawRect(Rect.fromLTWH(position.dx, position.dy, width, height),
        Paint()..color = Colors.grey.shade800);

    // Health fill
    canvas.drawRect(
        Rect.fromLTWH(position.dx, position.dy, width * healthPct, height),
        Paint()
          ..color = healthPct > 0.6
              ? Colors.green
              : healthPct > 0.3
                  ? Colors.orange
                  : Colors.red);

    // Border
    canvas.drawRect(
        Rect.fromLTWH(position.dx, position.dy, width, height),
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  // Check collisions with walls
  void checkCollision() {
    // Get the cell coordinates
    int cellX = (playerPos.dx / cellSize).floor();
    int cellY = (playerPos.dy / cellSize).floor();

    // Check bounds
    if (cellX < 0 || cellX >= mapWidth || cellY < 0 || cellY >= mapHeight) {
      // Out of bounds, move back
      playerPos = Offset(
        min(max(playerPos.dx, cellSize / 2), (mapWidth - 0.5) * cellSize),
        min(max(playerPos.dy, cellSize / 2), (mapHeight - 0.5) * cellSize),
      );
      return;
    }

    // Check wall collision
    if (map[cellY][cellX] == 1) {
      // Move player away from wall
      double centerX = (cellX + 0.5) * cellSize;
      double centerY = (cellY + 0.5) * cellSize;
      double dx = playerPos.dx - centerX;
      double dy = playerPos.dy - centerY;

      // Push player out of wall
      if (dx.abs() > dy.abs()) {
        playerPos = Offset(
          playerPos.dx + (dx > 0 ? 1 : -1) * 5,
          playerPos.dy,
        );
      } else {
        playerPos = Offset(
          playerPos.dx,
          playerPos.dy + (dy > 0 ? 1 : -1) * 5,
        );
      }
    }
  }

  // Check collisions with enemies
  void checkEnemyCollisions() {
    double collisionDistance = 30; // Distance to detect collision

    for (Enemy enemy in enemies) {
      if (!enemy.alive) continue;

      double dx = enemy.position.dx - playerPos.dx;
      double dy = enemy.position.dy - playerPos.dy;
      double distance = sqrt(dx * dx + dy * dy);

      if (distance < collisionDistance) {
        // Take damage from enemy collision
        health = max(0, health - 1);

        // Push player back
        playerPos = Offset(
            playerPos.dx - dx / distance * 5, playerPos.dy - dy / distance * 5);
      }
    }
  }

  @override
  KeyEventResult onKeyEvent(
      KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    // Update our set of currently pressed keys.
    this.keysPressed = keysPressed;

    // Handle enemy shooting with space key
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      if (gameOver) {
        _restartGame();
      } else if (shootCooldown <= 0) {
        shootEnemy();
      }
    }

    return KeyEventResult.handled;
  }

  @override
  void onTapDown(TapDownInfo info) {
    // Handle mouse click to shoot
    if (!gameOver && shootCooldown <= 0) {
      shootEnemy();
    }
  }

  // Shoot at enemies in front of the player
  void shootEnemy() {
    if (ammo <= 0) return; // No ammo left
    if (isShooting) return; // Already shooting

    // Start shooting animation
    isShooting = true;
    shootAnimTime = 0;

    // Set cooldown between shots
    shootCooldown = 0.4; // 0.4 seconds between shots

    ammo--; // Use one ammo

    // Cast a ray directly in front of the player (centered on the crosshair)
    double shootRange = 500; // Extended shooting distance

    // The ray always goes straight ahead from the crosshair
    double rayAngle = playerAngle;

    // Cast the ray
    for (double distance = 0; distance < shootRange; distance += 5) {
      double rayX = playerPos.dx + cos(rayAngle) * distance;
      double rayY = playerPos.dy + sin(rayAngle) * distance;
      int mapX = (rayX / cellSize).toInt();
      int mapY = (rayY / cellSize).toInt();

      // Check for wall hit
      if (mapX < 0 || mapX >= mapWidth || mapY < 0 || mapY >= mapHeight) {
        break; // Out of bounds
      }

      if (map[mapY][mapX] == 1) {
        break; // Hit a wall
      }

      // Check for enemy hit
      for (Enemy enemy in enemies) {
        if (!enemy.alive) continue;

        // Calculate distance to enemy at this point
        double dx = enemy.position.dx - rayX;
        double dy = enemy.position.dy - rayY;
        double distToEnemy = sqrt(dx * dx + dy * dy);

        // Check if ray is close enough to enemy center to count as a hit
        // This creates a circular hitbox around the enemy
        if (distToEnemy < enemy.size / 2) {
          // Hit enemy
          enemy.hit = true;
          enemy.hitTime = 0;

          // Calculate damage based on distance from player (closer = more damage)
          double playerToEnemyDist = sqrt(
              pow(enemy.position.dx - playerPos.dx, 2) +
                  pow(enemy.position.dy - playerPos.dy, 2));

          int damage = 30 + Random().nextInt(20); // Base damage 30-50

          // Apply distance modifier (up to 40% reduction at max range)
          double distanceModifier =
              1.0 - (playerToEnemyDist / shootRange * 0.4);
          damage = (damage * distanceModifier).round();

          // Apply the damage
          enemy.health = max(0, enemy.health - damage);

          // Check if enemy died
          if (enemy.health <= 0 && enemy.alive) {
            enemy.alive = false;
            score += 100; // Award 100 points for a kill

            // Chance to drop an item
            if (Random().nextDouble() < 0.3) {
              // 30% chance
              ItemType itemType =
                  Random().nextBool() ? ItemType.healthPack : ItemType.ammo;
              items.add(Item(enemy.position, itemType));
            }
          }

          return; // End the function after hitting an enemy
        }
      }
    }
  }
}
