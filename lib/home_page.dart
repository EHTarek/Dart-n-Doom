import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flame_audio/flame_audio.dart'; // Import flame_audio for sound
import 'package:doom_flutter/main.dart'
    as main_app; // Import this at the top of the file

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

  // New properties for enhanced behavior
  String enemyType = 'soldier'; // Types: 'soldier', 'heavy', 'scout'
  double hearingRadius = 150; // Distance at which enemy can hear player shots
  double patrolTimer = 0; // Timer for patrol behavior
  List<Offset> patrolPoints = []; // Points for patrol paths
  int currentPatrolPoint = 0; // Current patrol destination
  double alertness = 0; // Increases when suspicious, affects reaction time
  double visionConeAngle = pi / 2; // Width of vision cone (radians)
  double currentAngle = 0; // Current facing direction
  bool alerted = false; // True when enemy is alert to player presence

  Enemy(this.position, this.size, {this.color = Colors.red}) {
    // Randomize some enemy properties
    moveSpeed = 15 + Random().nextDouble() * 15; // Between 15-30
    isAggressive = Random().nextBool(); // 50% chance to be aggressive

    // Assign random enemy type
    final types = ['soldier', 'heavy', 'scout'];
    enemyType = types[Random().nextInt(types.length)];

    // Set properties based on enemy type
    switch (enemyType) {
      case 'soldier':
        health = 100;
        moveSpeed *= 1.0;
        hearingRadius = 150;
        visionConeAngle = pi / 2.5; // ~72 degrees
        break;
      case 'heavy':
        health = 200;
        moveSpeed *= 0.7; // Slower
        color = Colors.blue.shade800;
        hearingRadius = 120; // Poor hearing
        visionConeAngle = pi / 3; // ~60 degrees - narrower vision
        size *= 1.3; // Larger size
        break;
      case 'scout':
        health = 70;
        moveSpeed *= 1.5; // Faster
        color = Colors.green.shade800;
        hearingRadius = 200; // Better hearing
        visionConeAngle = pi / 1.8; // ~100 degrees - wider vision
        size *= 0.9; // Smaller size
        break;
    }

    // Randomly initialize facing direction
    currentAngle = Random().nextDouble() * 2 * pi;
  }

  // Check if enemy can see the player (for shooting)
  bool canSeePlayer(Offset playerPos, List<List<int>> map, double cellSize) {
    // Vector from enemy to player
    double dx = playerPos.dx - position.dx;
    double dy = playerPos.dy - position.dy;

    // Distance to player
    double distance = sqrt(dx * dx + dy * dy);

    // Too far to see
    double sightDistance = (enemyType == 'scout')
        ? 600
        : (enemyType == 'heavy')
            ? 400
            : 500;
    if (distance > sightDistance) return false;

    // Check if player is within vision cone
    double angleToPlayer = atan2(dy, dx);
    double angleDiff = (angleToPlayer - currentAngle).abs();
    // Normalize angle difference
    while (angleDiff > pi) angleDiff = 2 * pi - angleDiff;

    // If player is outside vision cone, enemy can't see player
    if (angleDiff > visionConeAngle / 2 && !alerted) {
      return false;
    }

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

    // Enemy can see player, update last known position and state
    lastKnownPlayerPos = playerPos;
    lastSeenPlayerTime = 0;

    // Become alerted if not already
    if (!alerted) {
      alerted = true;
    }

    // Update facing direction to look at player
    currentAngle = atan2(dy, dx);

    return true; // No walls blocking sight
  }

  // Check if enemy can hear player shooting
  bool canHearPlayer(Offset playerPos, bool playerShooting) {
    if (!playerShooting) return false;

    // Calculate distance to player
    double dx = playerPos.dx - position.dx;
    double dy = playerPos.dy - position.dy;
    double distance = sqrt(dx * dx + dy * dy);

    // Check if within hearing radius
    if (distance <= hearingRadius) {
      // Enemy heard the shot
      alertness += 0.3; // Increase alertness

      // If very close or already somewhat alert, become fully alerted
      if (distance < hearingRadius * 0.5 || alertness > 0.7) {
        alerted = true;
        lastKnownPlayerPos = playerPos;
        // Turn toward sound
        currentAngle = atan2(dy, dx);
        return true;
      }
    }

    return false;
  }

  // Generate random patrol points around current position
  void generatePatrolPoints(List<List<int>> map, double cellSize) {
    patrolPoints.clear();

    // Number of patrol points based on enemy type
    int numPoints = (enemyType == 'scout')
        ? 5
        : (enemyType == 'heavy')
            ? 2
            : 3;

    for (int i = 0; i < numPoints; i++) {
      // Try to find valid patrol points
      for (int attempt = 0; attempt < 10; attempt++) {
        // Random distance and angle from current position
        double distance = 100 + Random().nextDouble() * 200;
        double angle = Random().nextDouble() * 2 * pi;

        double x = position.dx + cos(angle) * distance;
        double y = position.dy + sin(angle) * distance;

        // Check if point is in an empty space
        int cellX = (x / cellSize).floor();
        int cellY = (y / cellSize).floor();

        if (cellX >= 0 &&
            cellX < map[0].length &&
            cellY >= 0 &&
            cellY < map.length &&
            map[cellY][cellX] == 0) {
          // Valid patrol point
          patrolPoints.add(Offset(x, y));
          break;
        }
      }
    }

    // Add current position as a fallback point
    if (patrolPoints.isEmpty) {
      patrolPoints.add(position);
    }
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

    // Update facing direction
    currentAngle = atan2(dy, dx);

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
    } else {
      // Try to slide along walls
      // Try X movement only
      cellX = (position.dx + dx * moveSpeed * dt / cellSize).floor();
      if (cellX >= 0 &&
          cellX < map[0].length &&
          cellY >= 0 &&
          cellY < map.length &&
          map[cellY][cellX] != 1) {
        position = Offset(position.dx + dx * moveSpeed * dt, position.dy);
      }
      // Try Y movement only
      else {
        cellY = (position.dy + dy * moveSpeed * dt / cellSize).floor();
        if (cellX >= 0 &&
            cellX < map[0].length &&
            cellY >= 0 &&
            cellY < map.length &&
            map[cellY][cellX] != 1) {
          position = Offset(position.dx, position.dy + dy * moveSpeed * dt);
        }
      }
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

  // UI state
  bool showControls = true; // Always show controls initially
  double controlsFadeTimer = 5.0; // Controls fade after 5 seconds
  bool controlsAlwaysOn = false; // Toggle for keeping controls visible

  // Screen effects
  Offset screenShakeOffset =
      Offset.zero; // Current screen shake position offset
  double screenShakeIntensity = 0; // How intense the shake should be
  double screenShakeDuration = 0; // How long the current shake should last
  double screenShakeMaxDuration = 0.5; // Maximum shake duration
  double bloodOverlayOpacity = 0; // Opacity of blood overlay effect

  // Audio state
  bool backgroundMusicPlaying = false;
  bool bulletSoundLoaded = false;

  // Graphics resources
  bool textureLoaded = false;
  ui.Image? brickTexture;
  ui.Image? enemyTexture;
  bool enemyTextureLoaded = false;
  ui.Image? gunTexture;
  bool gunTextureLoaded = false;
  ui.Image? healthIcon;
  ui.Image? ammoIcon;

  // Items list
  List<Item> items = [];

  // Simple map: 1 = wall, 0 = empty space.
  final List<List<int>> map = [
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
    [1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1],
    [1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1],
    [1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 0, 1, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1],
    [1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1],
    [1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1],
    [1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0, 1],
    [1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1],
    [1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 0, 1],
    [1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1],
    [1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0, 1],
    [1, 0, 1, 0, 1, 1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1],
    [1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1],
    [1, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1],
    [1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  ];
  final int mapWidth = 20;
  final int mapHeight = 20;
  final double cellSize = 64; // Each map cell size in world units

  // Player starting position and properties
  Offset playerPos = Offset(96, 96); // Starting in the first room
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

    // Initialize background music
    await _initializeBackgroundMusic();

    // Preload sound effects
    await _preloadSoundEffects();

    // Generate brick texture
    brickTexture = await _generateBrickTexture();
    textureLoaded = true;

    // Load enemy texture from assets
    enemyTexture = await _loadEnemyTexture();
    enemyTextureLoaded = true;

    // Load gun texture from assets
    gunTexture = await _loadGunTexture();
    gunTextureLoaded = true;

    // Load health and ammo icons
    healthIcon = await _loadImage('assets/images/health.png');
    ammoIcon = await _loadImage('assets/images/ammo.png');

    // Add enemies at strategic positions across the map
    // Room 1 - Top left area
    enemies.add(Enemy(const Offset(160, 352), 30));

    // Room 2 - Top right area
    enemies.add(Enemy(const Offset(1088, 160), 35));

    // Room 3 - Middle area
    enemies.add(Enemy(const Offset(480, 480), 32));

    // Room 4 - Bottom right area
    enemies.add(Enemy(const Offset(1088, 1088), 36));

    // Room 5 - Bottom left area
    enemies.add(Enemy(const Offset(224, 928), 28));

    // Corridor guards
    enemies.add(Enemy(const Offset(480, 736), 33));
    enemies.add(Enemy(const Offset(800, 544), 31));

    // More enemies based on difficulty
    if (difficulty >= 1) {
      enemies.add(Enemy(const Offset(352, 672), 34));
      enemies.add(Enemy(const Offset(928, 800), 29));
    }

    // Even more enemies on hard difficulty
    if (difficulty >= 2) {
      enemies.add(Enemy(const Offset(640, 192), 37));
      enemies.add(Enemy(const Offset(800, 928), 30));
      enemies.add(Enemy(const Offset(320, 480), 35));
    }

    // Generate patrol paths for some enemies
    for (Enemy enemy in enemies) {
      if (Random().nextDouble() < 0.7) {
        enemy.generatePatrolPoints(map, cellSize);
      }
    }

    // Spawn some initial items
    _spawnItems();
  }

  // Load an image from assets
  Future<ui.Image> _loadImage(String assetPath) async {
    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo fi = await codec.getNextFrame();
    return fi.image;
  }

  // Initialize and start background music
  Future<void> _initializeBackgroundMusic() async {
    try {
      print('Checking background music status in game...');

      // Check global audio state from main.dart
      if (main_app.audioInitialized) {
        // Music is already playing from the home screen, just set the flag
        backgroundMusicPlaying = true;
        print('Music already playing from home screen, continuing playback');
      } else {
        // Music not started yet, start it now
        print('Starting background music in game...');
        await FlameAudio.bgm.play('backgroundMusic.mp3', volume: 0.7);
        backgroundMusicPlaying = true;
        main_app.audioInitialized = true;
        print('Background music started in game');
      }
    } catch (e) {
      print('Error with background music in game: $e');
      backgroundMusicPlaying = false;
    }
  }

  @override
  void onRemove() {
    // Stop any music or sounds when game is closed
    if (backgroundMusicPlaying) {
      FlameAudio.bgm.stop();
    }
    super.onRemove();
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

    // Apply screen shake effect
    if (screenShakeDuration > 0) {
      canvas.translate(screenShakeOffset.dx, screenShakeOffset.dy);
    }

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

    // Draw DOOM-style HUD at the bottom
    _drawDoomHUD(canvas, size);

    // Draw damage indicator when hurt
    if (damageIndicatorTime > 0) {
      // Red flash with opacity based on damage amount and time remaining
      double opacity = damageIndicatorTime * min(0.7, lastDamageAmount / 30.0);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()..color = Colors.red.withOpacity(opacity),
      );
    }

    // Draw blood overlay effect (more realistic gore effect)
    if (bloodOverlayOpacity > 0) {
      // Draw blood splatter at edges of screen
      final bloodPaint = Paint()
        ..color = Colors.red.shade900.withOpacity(bloodOverlayOpacity);

      // Add some random blood drips at the top
      if (bloodOverlayOpacity > 0.3) {
        final Random rnd = Random();
        final bloodPath = Path();

        for (int i = 0; i < 8; i++) {
          double startX = rnd.nextDouble() * size.x;
          double length = 20.0 + rnd.nextDouble() * 100;

          bloodPath.moveTo(startX, 0);
          bloodPath.lineTo(startX - 5 + rnd.nextDouble() * 10, length);
          bloodPath.lineTo(startX + 10, length);
          bloodPath.lineTo(startX + 5, 0);
          bloodPath.close();
        }

        canvas.drawPath(bloodPath, bloodPaint);
      }

      // Add vignette effect that gets stronger as health decreases
      final healthFactor = 1.0 - (health / 100.0);
      final vignetteRect = Rect.fromLTWH(0, 0, size.x, size.y);
      final vignetteRadius = size.x * 0.8 * (1.0 - healthFactor * 0.5);

      final vignetteGradient = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Colors.transparent,
          Colors.red.shade900.withOpacity(bloodOverlayOpacity * 0.7),
        ],
        stops: [0.6 * (1.0 - healthFactor * 0.3), 1.0],
      );

      canvas.drawRect(
        vignetteRect,
        Paint()..shader = vignetteGradient.createShader(vignetteRect),
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

    // Draw controls panel at the top of the screen - drawn last so it stays on top
    if (showControls) {
      _drawControlsPanel(canvas, size);
    }
  }

  // Draw enemies as sprites in the 3D view
  void _drawEnemies(
      Canvas canvas, Vector2 size, List<double> zBuffer, double fov) {
    // Sort enemies by distance for proper rendering order (furthest first)
    List<Enemy> sortedEnemies = List.from(enemies);
    sortedEnemies.sort((a, b) {
      double distA = sqrt(pow(a.position.dx - playerPos.dx, 2) +
          pow(a.position.dy - playerPos.dy, 2));
      double distB = sqrt(pow(b.position.dx - playerPos.dx, 2) +
          pow(b.position.dy - playerPos.dy, 2));
      // Sort in descending order (furthest first)
      return distB.compareTo(distA);
    });

    for (Enemy enemy in sortedEnemies) {
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

      // Check if enemy is in field of view (with larger buffer)
      // Added extra buffer for better visibility when aiming
      if (angle.abs() > fov / 2 + 0.3) continue;

      // Calculate screen position
      double screenX = (size.x / 2) + tan(angle) * (size.x / 2);

      // Calculate sprite height based on distance and enemy size
      double spriteHeight = size.y / distance * enemy.size;

      // Ensure the sprite has a minimum height for visibility
      spriteHeight = max(spriteHeight, 20.0);

      // Calculate sprite width based on height (keep ratio)
      double spriteWidth = spriteHeight * 0.6;

      // Ensure the sprite has a minimum width for visibility
      spriteWidth = max(spriteWidth, 12.0);

      // The range of x-coordinates the sprite will occupy on screen
      int spriteLeftX = (screenX - spriteWidth / 2).floor();
      int spriteRightX = (screenX + spriteWidth / 2).ceil();

      // Ensure sprite is fully visible by clamping to screen boundaries
      if (spriteLeftX < 0) spriteLeftX = 0;
      if (spriteRightX >= size.x) spriteRightX = size.x.toInt() - 1;

      // Loop through each vertical strip of the sprite
      for (int x = spriteLeftX; x <= spriteRightX; x++) {
        // Only render if in front of a wall and within screen bounds
        if (x >= 0 && x < size.x && distance < zBuffer[x]) {
          // Calculate top position of sprite
          double spriteTop = size.y / 2 - spriteHeight / 2;

          // Create rectangle for this vertical slice of the enemy
          final double sliceWidth = 1.0; // Width of one vertical slice
          final enemySliceRect = Rect.fromLTWH(
            x.toDouble(),
            spriteTop,
            sliceWidth,
            spriteHeight,
          );

          // Calculate the relative position within the sprite texture
          final double texturePosX =
              (x - spriteLeftX) / (spriteRightX - spriteLeftX);
          final Rect srcRect = Rect.fromLTWH(
              texturePosX * enemyTexture!.width,
              0,
              enemyTexture!.width / (spriteRightX - spriteLeftX),
              enemyTexture!.height.toDouble());

          if (enemyTextureLoaded && enemyTexture != null) {
            // Create paint with appropriate effects
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

            // Draw the image slice
            canvas.drawImageRect(
              enemyTexture!,
              srcRect,
              enemySliceRect,
              paint,
            );
          } else {
            // Fallback to drawing soldier if texture isn't loaded
            _drawSoldierEnemy(canvas, enemySliceRect, enemy, distance);
          }
        }
      }

      // Draw health bar above enemy
      double spriteTop = size.y / 2 - spriteHeight / 2;
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
        double flashY =
            spriteTop + spriteHeight * 0.4; // Adjust based on your enemy image

        canvas.drawCircle(
            Offset(flashX, flashY), spriteWidth * 0.1, flashPaint);

        canvas.drawCircle(
            Offset(flashX, flashY), spriteWidth * 0.05, innerFlashPaint);
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

    // Check if background music needs to be restarted
    _checkBackgroundMusic();

    // Handle screen shake timing
    if (screenShakeDuration > 0) {
      screenShakeDuration -= dt;
      if (screenShakeDuration <= 0) {
        screenShakeOffset = Offset.zero;
      } else {
        // Update screen shake effect
        double intensity = screenShakeIntensity *
            (screenShakeDuration / screenShakeMaxDuration);
        screenShakeOffset = Offset(
            Random().nextDouble() * intensity * 2 - intensity,
            Random().nextDouble() * intensity * 2 - intensity);
      }
    }

    // Handle controls fade timer
    if (!controlsAlwaysOn && controlsFadeTimer > 0) {
      controlsFadeTimer -= dt;
      if (controlsFadeTimer <= 0) {
        showControls = false;
      }
    }

    // Reset controls timer on movement to make controls appear again
    if (!showControls &&
        (keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
            keysPressed.contains(LogicalKeyboardKey.keyW) ||
            keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
            keysPressed.contains(LogicalKeyboardKey.keyS) ||
            keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
            keysPressed.contains(LogicalKeyboardKey.keyA) ||
            keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
            keysPressed.contains(LogicalKeyboardKey.keyD))) {
      showControls = true;
      controlsFadeTimer = 5.0;
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

    // Update blood overlay effect
    if (bloodOverlayOpacity > 0) {
      bloodOverlayOpacity -= dt * 0.3; // Fade out gradually
      if (bloodOverlayOpacity < 0) bloodOverlayOpacity = 0;
    }

    // Update items
    _updateItems(dt);

    // Check for item pickups
    _checkItemPickups();

    // Update enemies
    _updateEnemies(dt);

    // Check collisions with walls
    checkCollision();

    // Check collisions with enemies
    checkEnemyCollisions();
  }

  // Add a screen shake effect when player takes damage
  void addScreenShake(double amount) {
    screenShakeIntensity = amount.clamp(0, 20); // Limit max intensity
    screenShakeDuration = screenShakeMaxDuration;
  }

  // Check and ensure background music is playing
  void _checkBackgroundMusic() {
    if (!backgroundMusicPlaying) {
      // Try to start background music again if it's not playing
      try {
        print('Restarting background music in game...');
        FlameAudio.bgm.play('backgroundMusic.mp3', volume: 0.7);
        backgroundMusicPlaying = true;
      } catch (e) {
        print('Failed to restart background music: $e');
      }
    }
  }

  // Toggle background music on/off
  void toggleBackgroundMusic() {
    if (backgroundMusicPlaying) {
      FlameAudio.bgm.stop();
      backgroundMusicPlaying = false;
    } else {
      FlameAudio.bgm.play('backgroundMusic.mp3', volume: 0.7);
      backgroundMusicPlaying = true;
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

      // Increment patrol timer
      enemy.patrolTimer += dt;

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

      // Check if enemy can hear player shooting
      if (isShooting) {
        enemy.canHearPlayer(playerPos, isShooting);
      }

      // Gradually reduce alertness over time
      if (enemy.alertness > 0 && !enemy.alerted) {
        enemy.alertness = max(0, enemy.alertness - dt * 0.05);
      }

      // Enemy AI state machine
      bool canSee = enemy.canSeePlayer(playerPos, map, cellSize);

      // Main enemy behavior states
      if (canSee) {
        // Enemy can see player
        if (enemy.shootCooldown <= 0) {
          // Try to shoot
          _enemyShoot(enemy);
        }

        // Combat movement - different behaviors based on enemy type
        double preferredDistance = 0;

        switch (enemy.enemyType) {
          case 'soldier':
            // Soldiers try to maintain medium distance
            preferredDistance = 200;
            break;
          case 'heavy':
            // Heavy enemies try to get closer
            preferredDistance = 150;
            break;
          case 'scout':
            // Scouts prefer to stay at a distance
            preferredDistance = 300;
            break;
        }

        // Calculate current distance to player
        double dx = playerPos.dx - enemy.position.dx;
        double dy = playerPos.dy - enemy.position.dy;
        double distanceToPlayer = sqrt(dx * dx + dy * dy);

        // If too close, back away
        if (distanceToPlayer < preferredDistance * 0.7) {
          // Move away from player
          Offset retreatPos = Offset(
              enemy.position.dx - dx * 0.5, enemy.position.dy - dy * 0.5);
          enemy.moveTowards(retreatPos, dt, map, cellSize);
        }
        // If too far, approach
        else if (distanceToPlayer > preferredDistance * 1.3) {
          // Move towards player
          double approachFactor = enemy.enemyType == 'scout' ? 0.7 : 1.0;
          Offset approachPos = Offset(playerPos.dx - dx * 0.2 * approachFactor,
              playerPos.dy - dy * 0.2 * approachFactor);
          enemy.moveTowards(approachPos, dt, map, cellSize);
        }
        // If at good distance, strafe
        else if (Random().nextDouble() < 0.02) {
          // Random strafing movement perpendicular to player
          double strafeAngle =
              atan2(dy, dx) + (Random().nextBool() ? pi / 2 : -pi / 2);
          double strafeDist = 30 + Random().nextDouble() * 30;

          Offset strafePos = Offset(
              enemy.position.dx + cos(strafeAngle) * strafeDist,
              enemy.position.dy + sin(strafeAngle) * strafeDist);
          enemy.moveTowards(strafePos, dt, map, cellSize);
        }
      } else if (enemy.alerted && enemy.lastSeenPlayerTime < 7.0) {
        // Enemy lost sight but is still alerted - search behavior

        // Move to last known position first
        double dx = enemy.lastKnownPlayerPos.dx - enemy.position.dx;
        double dy = enemy.lastKnownPlayerPos.dy - enemy.position.dy;
        double distToLastSeen = sqrt(dx * dx + dy * dy);

        if (distToLastSeen > 20) {
          // Still moving to last seen position
          enemy.moveTowards(enemy.lastKnownPlayerPos, dt, map, cellSize);
        } else {
          // At last seen position, look around
          enemy.patrolTimer += dt;

          // Change direction every 2 seconds
          if (enemy.patrolTimer > 2.0) {
            enemy.patrolTimer = 0;
            enemy.currentAngle += (Random().nextDouble() - 0.5) * pi;
          }

          // Move in current facing direction
          Offset searchPos = Offset(
              enemy.position.dx + cos(enemy.currentAngle) * 40,
              enemy.position.dy + sin(enemy.currentAngle) * 40);
          enemy.moveTowards(searchPos, dt, map, cellSize);
        }

        // Gradually reduce alert status
        if (enemy.lastSeenPlayerTime > 5.0) {
          enemy.alerted = false;
        }
      } else if (enemy.isAggressive && enemy.patrolPoints.isEmpty) {
        // Generate patrol points for aggressive enemies
        enemy.generatePatrolPoints(map, cellSize);
      } else if (!enemy.patrolPoints.isEmpty) {
        // Patrol behavior - move between patrol points
        if (enemy.currentPatrolPoint >= enemy.patrolPoints.length) {
          enemy.currentPatrolPoint = 0;
        }

        Offset target = enemy.patrolPoints[enemy.currentPatrolPoint];
        enemy.moveTowards(target, dt, map, cellSize);

        // Check if reached patrol point
        double dx = target.dx - enemy.position.dx;
        double dy = target.dy - enemy.position.dy;
        double distToTarget = sqrt(dx * dx + dy * dy);

        if (distToTarget < 10) {
          // Move to next patrol point
          enemy.currentPatrolPoint =
              (enemy.currentPatrolPoint + 1) % enemy.patrolPoints.length;

          // Pause at waypoint
          enemy.patrolTimer = 0;
        }
      } else if (Random().nextDouble() < 0.008) {
        // Random movement occasionally
        double randomAngle = Random().nextDouble() * 2 * pi;
        double moveDistance =
            30 + Random().nextDouble() * 30; // How far to move

        Offset target = Offset(
            enemy.position.dx + cos(randomAngle) * moveDistance,
            enemy.position.dy + sin(randomAngle) * moveDistance);

        enemy.moveTowards(target, dt, map, cellSize);
      }
    }

    // Spawn new enemies if few remain
    if (enemies.length < 5 && Random().nextDouble() < 0.003) {
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

        if (distanceToPlayer > 300) {
          // Not too close to player
          // Create enemy with appropriate properties
          Enemy newEnemy = Enemy(pos, 30 + random.nextDouble() * 15);

          // Add to enemies list
          enemies.add(newEnemy);

          // Generate patrol points
          if (random.nextDouble() < 0.7) {
            newEnemy.generatePatrolPoints(map, cellSize);
          }

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

    // Cooldown time depends on enemy type
    double baseCooldown = 0;
    switch (enemy.enemyType) {
      case 'soldier':
        baseCooldown = 1.5; // Standard cooldown
        break;
      case 'heavy':
        baseCooldown = 2.5; // Slower firing rate
        break;
      case 'scout':
        baseCooldown = 1.0; // Faster firing rate
        break;
    }

    // Add randomization to cooldown
    enemy.shootCooldown = baseCooldown + Random().nextDouble() * 1.0;

    // Vector from enemy to player
    double dx = playerPos.dx - enemy.position.dx;
    double dy = playerPos.dy - enemy.position.dy;
    double distance = sqrt(dx * dx + dy * dy);

    // Base hit chance depends on distance and enemy type
    double accuracyFactor = 0;
    switch (enemy.enemyType) {
      case 'soldier':
        accuracyFactor = 1.0; // Standard accuracy
        break;
      case 'heavy':
        accuracyFactor = 0.8; // Less accurate
        break;
      case 'scout':
        accuracyFactor = 1.2; // More accurate
        break;
    }

    // Player movement reduces enemy accuracy
    bool playerMoving = keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW) ||
        keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
        keysPressed.contains(LogicalKeyboardKey.keyS);

    if (playerMoving) {
      accuracyFactor *= 0.8; // 20% accuracy reduction when player is moving
    }

    // Calculate final hit chance
    double hitChance = (1.0 - (distance / 500)) * accuracyFactor;
    hitChance = hitChance.clamp(0.1, 0.9); // Min 10%, max 90% hit chance

    // Check if enemy hits the player
    if (Random().nextDouble() < hitChance) {
      // Player is hit, reduce health
      // Damage depends on enemy type and distance
      int baseDamage = 0;
      switch (enemy.enemyType) {
        case 'soldier':
          baseDamage = 10; // Standard damage
          break;
        case 'heavy':
          baseDamage = 15; // More damage
          break;
        case 'scout':
          baseDamage = 7; // Less damage
          break;
      }

      // Distance modifier - closer enemies do more damage
      double distanceFactor = 1.0 - (distance / 500).clamp(0.0, 0.8);
      int damageBoost = (distanceFactor * 10).round();

      // Calculate final damage with randomization
      int damage = baseDamage + damageBoost + Random().nextInt(5);

      // Difficulty affects damage taken
      if (difficulty == 0) {
        // Easy
        damage = (damage * 0.7).round(); // 30% damage reduction
      } else if (difficulty == 2) {
        // Hard
        damage = (damage * 1.3).round(); // 30% damage increase
      }

      // Handle critical hits (10% chance)
      bool isCritical = Random().nextDouble() < 0.1;
      if (isCritical) {
        damage = (damage * 1.5).round(); // Critical hit does 50% more damage
      }

      // Apply damage
      health = max(0, health - damage);

      // Set damage indicator with longer duration for more damage
      double indicatorDuration =
          0.5 + (damage / 50.0); // Up to 1 second for high damage
      damageIndicatorTime = min(indicatorDuration, 1.0);
      lastDamageAmount = damage.toDouble();

      // Add screen shake effect based on damage amount
      addScreenShake(damage * 0.3);

      // Add blood overlay effect
      bloodOverlayOpacity = min(0.7, bloodOverlayOpacity + damage * 0.02);

      // Play hit sound (if available)
      _playSoundEffect('hit', volume: 0.3);

      // Show visual damage indicators based on health
      // This is handled in HUD and screen effects

      // Check for game over
      if (health <= 0) {
        gameOver = true;
        // Could add death sound here
      }
    } else {
      // Enemy missed - show near miss effect if very close
      if (hitChance > 0.7) {
        // Near miss - could add visual cue or sound
      }
    }
  }

  // Restart game with music
  void _restartGame() {
    // Reset player state
    health = 100;
    ammo = 50;
    playerPos = Offset(96, 96); // Starting position in first room
    playerAngle = 0;
    score = 0;
    gameOver = false;

    // Set difficulty-specific parameters
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

    // Check if music needs to be restarted
    if (!backgroundMusicPlaying && main_app.audioInitialized) {
      // Music was previously playing but stopped
      FlameAudio.bgm.play('backgroundMusic.mp3', volume: 0.7);
      backgroundMusicPlaying = true;
    } else if (!backgroundMusicPlaying && !main_app.audioInitialized) {
      // First time playing after restart
      _initializeBackgroundMusic();
    }

    // Clear and respawn enemies
    enemies.clear();

    // Add enemies at strategic positions across the map
    // Room 1 - Top left area
    enemies.add(Enemy(const Offset(160, 352), 30));

    // Room 2 - Top right area
    enemies.add(Enemy(const Offset(1088, 160), 35));

    // Room 3 - Middle area
    enemies.add(Enemy(const Offset(480, 480), 32));

    // Room 4 - Bottom right area
    enemies.add(Enemy(const Offset(1088, 1088), 36));

    // Room 5 - Bottom left area
    enemies.add(Enemy(const Offset(224, 928), 28));

    // Corridor guards
    enemies.add(Enemy(const Offset(480, 736), 33));
    enemies.add(Enemy(const Offset(800, 544), 31));

    // More enemies based on difficulty
    if (difficulty >= 1) {
      enemies.add(Enemy(const Offset(352, 672), 34));
      enemies.add(Enemy(const Offset(928, 800), 29));
    }

    // Even more enemies on hard difficulty
    if (difficulty >= 2) {
      enemies.add(Enemy(const Offset(640, 192), 37));
      enemies.add(Enemy(const Offset(800, 928), 30));
      enemies.add(Enemy(const Offset(320, 480), 35));
    }

    // Generate patrol paths for some enemies
    for (Enemy enemy in enemies) {
      if (Random().nextDouble() < 0.7) {
        enemy.generatePatrolPoints(map, cellSize);
      }
    }

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

    // Check if crosshair is over an enemy
    bool isOverEnemy = false;
    double distanceToEnemy = double.infinity;

    // Cast a ray from the center of the screen
    double rayAngle = playerAngle;
    for (double distance = 0; distance < 500; distance += 5) {
      double rayX = playerPos.dx + cos(rayAngle) * distance;
      double rayY = playerPos.dy + sin(rayAngle) * distance;

      // Check for wall hit
      int mapX = (rayX / cellSize).toInt();
      int mapY = (rayY / cellSize).toInt();

      if (mapX < 0 ||
          mapX >= mapWidth ||
          mapY < 0 ||
          mapY >= mapHeight ||
          map[mapY][mapX] == 1) {
        break; // Hit a wall or out of bounds
      }

      // Check for enemy hit
      for (Enemy enemy in enemies) {
        if (!enemy.alive) continue;

        double dx = enemy.position.dx - rayX;
        double dy = enemy.position.dy - rayY;
        double distToEnemy = sqrt(dx * dx + dy * dy);

        if (distToEnemy < enemy.size / 2 + 5) {
          isOverEnemy = true;
          distanceToEnemy = sqrt(pow(enemy.position.dx - playerPos.dx, 2) +
              pow(enemy.position.dy - playerPos.dy, 2));
          break;
        }
      }

      if (isOverEnemy) break;
    }

    // Determine crosshair color - red when over enemy, white otherwise
    final Color crosshairColor = isOverEnemy ? Colors.red : Colors.white;

    // Add a subtle pulse animation when aiming at an enemy
    double crosshairSize = 10.0; // Base size
    double strokeWidth = 2.0;

    if (isOverEnemy) {
      // Calculate size based on enemy distance (closer = larger crosshair)
      double distanceFactor = 1.0 - min(1.0, distanceToEnemy / 500);
      crosshairSize = 10.0 + (distanceFactor * 5.0);
      strokeWidth = 2.0 + (distanceFactor * 1.5);
    }

    // Add a slight spread indication when moving or recently shot
    if (isShooting) {
      crosshairSize += 6.0 * (1.0 - min(1.0, shootAnimTime / 0.3));
    }

    // Configure crosshair style
    final crosshairPaint = Paint()
      ..color = crosshairColor
      ..strokeWidth = strokeWidth;

    // Create a subtle glow effect when over an enemy
    if (isOverEnemy) {
      // First draw a larger, transparent crosshair for the glow effect
      final glowPaint = Paint()
        ..color = Colors.red.withOpacity(0.3)
        ..strokeWidth = strokeWidth + 2.0;

      // Draw glow crosshair
      canvas.drawLine(
        Offset(centerX - crosshairSize - 4, centerY),
        Offset(centerX + crosshairSize + 4, centerY),
        glowPaint,
      );

      canvas.drawLine(
        Offset(centerX, centerY - crosshairSize - 4),
        Offset(centerX, centerY + crosshairSize + 4),
        glowPaint,
      );
    }

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

    // Draw a small circle in the center
    canvas.drawCircle(
      Offset(centerX, centerY),
      isOverEnemy ? 3 : 2,
      crosshairPaint,
    );

    // Add aiming dots around the circle for better precision
    if (isOverEnemy) {
      final double dotRadius = 1.5;
      final double dotDistance = crosshairSize * 0.5;

      // Draw 4 small dots around the center in a diamond pattern
      canvas.drawCircle(
        Offset(centerX + dotDistance, centerY),
        dotRadius,
        crosshairPaint,
      );

      canvas.drawCircle(
        Offset(centerX - dotDistance, centerY),
        dotRadius,
        crosshairPaint,
      );

      canvas.drawCircle(
        Offset(centerX, centerY + dotDistance),
        dotRadius,
        crosshairPaint,
      );

      canvas.drawCircle(
        Offset(centerX, centerY - dotDistance),
        dotRadius,
        crosshairPaint,
      );
    }
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
    for (Enemy enemy in enemies) {
      if (!enemy.alive) continue;

      double dx = enemy.position.dx - playerPos.dx;
      double dy = enemy.position.dy - playerPos.dy;
      double distance = sqrt(dx * dx + dy * dy);

      // Base collision distance depends on enemy type
      double baseCollisionDistance = 30;
      double damageMultiplier = 1.0;

      switch (enemy.enemyType) {
        case 'soldier':
          baseCollisionDistance = 30; // Standard
          damageMultiplier = 1.0;
          break;
        case 'heavy':
          baseCollisionDistance = 35; // Larger
          damageMultiplier = 1.5; // More damage
          break;
        case 'scout':
          baseCollisionDistance = 25; // Smaller
          damageMultiplier = 0.8; // Less damage
          break;
      }

      // Apply damage based on collision distance
      if (distance < baseCollisionDistance) {
        // Determine damage based on enemy type and difficulty
        int baseMeleeDamage = (5 * damageMultiplier).round();

        // Adjust for difficulty
        if (difficulty == 0) {
          // Easy
          baseMeleeDamage = (baseMeleeDamage * 0.7).round();
        } else if (difficulty == 2) {
          // Hard
          baseMeleeDamage = (baseMeleeDamage * 1.3).round();
        }

        // Additional damage if enemy is rushing at player
        if (enemy.alerted) {
          baseMeleeDamage = (baseMeleeDamage * 1.2).round();
        }

        // Apply damage
        health = max(0, health - baseMeleeDamage);
        damageIndicatorTime = 0.3; // Short flash for melee damage
        lastDamageAmount = baseMeleeDamage.toDouble();

        // Add screen shake for melee hit
        addScreenShake(baseMeleeDamage * 0.5); // More intense for melee

        // Add blood overlay effect
        bloodOverlayOpacity =
            min(0.7, bloodOverlayOpacity + baseMeleeDamage * 0.03);

        // Push player back based on enemy type
        double pushForce = (enemy.enemyType == 'heavy') ? 8.0 : 5.0;
        playerPos = Offset(playerPos.dx - dx / distance * pushForce,
            playerPos.dy - dy / distance * pushForce);

        // Also push enemy back slightly (except for heavy type)
        if (enemy.enemyType != 'heavy') {
          enemy.position = Offset(enemy.position.dx + dx / distance * 3.0,
              enemy.position.dy + dy / distance * 3.0);
        }

        // Make enemy alerted after contact
        enemy.alerted = true;

        // Play collision sound
        _playSoundEffect('collision', volume: 0.3);
      }

      // Proximity awareness - enemies become alerted when player is very close
      else if (distance < baseCollisionDistance * 3 && !enemy.alerted) {
        // Chance to notice player based on distance
        double noticeChance = 1.0 - (distance / (baseCollisionDistance * 3));

        if (Random().nextDouble() < noticeChance) {
          enemy.alerted = true;
          enemy.lastKnownPlayerPos = playerPos;
        }
      }
    }

    // Check if game over from damage
    if (health <= 0) {
      gameOver = true;
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

    // Toggle music with M key
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyM) {
      toggleBackgroundMusic();
    }

    // Toggle controls visibility with H key
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyH) {
      controlsAlwaysOn = !controlsAlwaysOn;
      if (controlsAlwaysOn) {
        showControls = true;
      } else {
        controlsFadeTimer = 5.0; // Start fade timer when toggled off
      }
    }

    return KeyEventResult.handled;
  }

  @override
  void onTapDown(TapDownInfo info) {
    if (gameOver) {
      _restartGame();
    } else if (shootCooldown <= 0) {
      // Play shooting sound and perform shooting
      shootEnemy();
    }
  }

  // Shoot at enemies in front of the player
  void shootEnemy() {
    if (ammo <= 0 || shootCooldown > 0) {
      return;
    }

    // Play bullet shot sound
    _playSoundEffect('shoot', volume: 0.5);

    // Reduce ammo and set cooldown
    ammo--;
    shootCooldown = 0.5; // Half a second cooldown between shots
    isShooting = true;
    shootAnimTime = 0.3; // Animation time for muzzle flash

    // Calculate shooting range
    final double shootRange = 500;

    // Track if we've hit anything
    bool hitSomething = false;

    // The ray goes straight ahead from the crosshair (player's angle)
    double rayAngle = playerAngle;

    // Add a small spread for more forgiving hit detection
    // We'll cast 3 rays: one straight ahead and two slightly offset
    List<double> angleOffsets = [
      -0.05,
      0.0,
      0.05
    ]; // Small angle offsets in radians

    // Try each ray with slight angle variations
    for (double angleOffset in angleOffsets) {
      if (hitSomething) break; // Stop if we already hit something

      double currentAngle = rayAngle + angleOffset;

      // Cast the ray
      for (double distance = 0; distance < shootRange; distance += 5) {
        double rayX = playerPos.dx + cos(currentAngle) * distance;
        double rayY = playerPos.dy + sin(currentAngle) * distance;
        int mapX = (rayX / cellSize).toInt();
        int mapY = (rayY / cellSize).toInt();

        // Check for wall hit
        if (mapX < 0 || mapX >= mapWidth || mapY < 0 || mapY >= mapHeight) {
          break; // Out of bounds
        }

        if (map[mapY][mapX] == 1) {
          break; // Hit a wall
        }

        // Check for enemy hit with improved detection
        for (Enemy enemy in enemies) {
          if (!enemy.alive) continue;

          // Calculate distance to enemy at this point
          double dx = enemy.position.dx - rayX;
          double dy = enemy.position.dy - rayY;
          double distToEnemy = sqrt(dx * dx + dy * dy);

          // Use a slightly larger hitbox for better hit detection
          double hitboxSize = enemy.size / 2 +
              5; // Adding 5 units for more forgiving hit detection

          // Check if ray is close enough to enemy center to count as a hit
          if (distToEnemy < hitboxSize) {
            // Hit enemy
            enemy.hit = true;
            enemy.hitTime = 0;
            hitSomething = true;

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

  // Add this method to draw the pixelated DOOM HUD
  void _drawDoomHUD(Canvas canvas, Vector2 size) {
    const double hudHeight = 80;
    const double margin = 10;

    // Draw black background for HUD
    final hudRect = Rect.fromLTWH(0, size.y - hudHeight, size.x, hudHeight);
    canvas.drawRect(hudRect, Paint()..color = Colors.black);

    // Draw divider line
    canvas.drawLine(
      Offset(0, size.y - hudHeight),
      Offset(size.x, size.y - hudHeight),
      Paint()
        ..color = Colors.grey.shade800
        ..strokeWidth = 3,
    );

    // Draw pixelated stats
    final statWidth = size.x / 5;

    // AMMO display with icon
    if (ammoIcon != null) {
      // Draw ammo icon
      final iconSize = 32.0;
      final iconRect = Rect.fromLTWH(
          margin, size.y - hudHeight + margin, iconSize, iconSize);
      canvas.drawImageRect(
          ammoIcon!,
          Rect.fromLTWH(
              0, 0, ammoIcon!.width.toDouble(), ammoIcon!.height.toDouble()),
          iconRect,
          Paint());

      // Draw ammo count
      _drawPixelatedNumber(
        canvas,
        '$ammo',
        Offset(margin + iconSize + 5, size.y - hudHeight + margin + 5),
        Colors.red,
        large: true,
      );
    } else {
      // Fallback if icon not loaded
      _drawPixelatedNumber(
        canvas,
        '$ammo',
        Offset(margin, size.y - hudHeight + margin),
        Colors.red,
        large: true,
      );
    }
    _drawStatusLabel(
      canvas,
      'AMMO',
      Offset(margin, size.y - 18),
      Colors.grey,
    );

    // HEALTH display with icon
    if (healthIcon != null) {
      // Draw health icon
      final iconSize = 32.0;
      final iconRect = Rect.fromLTWH(
          statWidth + margin, size.y - hudHeight + margin, iconSize, iconSize);
      canvas.drawImageRect(
          healthIcon!,
          Rect.fromLTWH(0, 0, healthIcon!.width.toDouble(),
              healthIcon!.height.toDouble()),
          iconRect,
          Paint());

      // Draw health count
      _drawPixelatedNumber(
        canvas,
        '$health%',
        Offset(
            statWidth + margin + iconSize + 5, size.y - hudHeight + margin + 5),
        Colors.red,
        large: true,
      );
    } else {
      // Fallback if icon not loaded
      _drawPixelatedNumber(
        canvas,
        '$health%',
        Offset(statWidth + margin, size.y - hudHeight + margin),
        Colors.red,
        large: true,
      );
    }
    _drawStatusLabel(
      canvas,
      'HEALTH',
      Offset(statWidth + margin, size.y - 18),
      Colors.grey,
    );

    // Draw weapon slots (3x3 grid)
    final double weaponGridLeft = statWidth * 2 + margin;
    final double weaponGridTop = size.y - hudHeight + margin;
    final double cellSize = (hudHeight - margin * 2) / 3;

    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final weaponSlot = row * 3 + col + 1;
        final cellRect = Rect.fromLTWH(
          weaponGridLeft + col * cellSize,
          weaponGridTop + row * cellSize,
          cellSize - 2,
          cellSize - 2,
        );

        // Draw cell background
        canvas.drawRect(
          cellRect,
          Paint()..color = Colors.grey.shade800,
        );

        // Draw weapon number
        TextPainter textPainter = TextPainter(
          text: TextSpan(
            text: '$weaponSlot',
            style: TextStyle(
              color: Colors.yellow,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            cellRect.left + (cellRect.width - textPainter.width) / 2,
            cellRect.top + (cellRect.height - textPainter.height) / 2,
          ),
        );
      }
    }

    // Face display in the center
    final faceSize = hudHeight - margin * 2;
    final faceRect = Rect.fromLTWH(
      (size.x - faceSize) / 2,
      size.y - hudHeight + margin,
      faceSize,
      faceSize,
    );

    // Draw face background
    canvas.drawRect(
      faceRect,
      Paint()..color = Colors.grey.shade900,
    );

    // Draw face - changes based on health
    _drawDoomFace(canvas, faceRect, health);

    // ARMOR display
    final armorValue = 0; // You can add armor as a game mechanic later
    _drawPixelatedNumber(
      canvas,
      '$armorValue%',
      Offset(size.x - statWidth - margin - 40, size.y - hudHeight + margin),
      Colors.red,
      large: true,
    );
    _drawStatusLabel(
      canvas,
      'ARMOR',
      Offset(size.x - statWidth - margin - 40, size.y - 18),
      Colors.grey,
    );

    // Draw stats like ammo types
    final double rightStatsX = size.x - margin - 80;
    final double rightStatsY = size.y - hudHeight + margin;

    _drawStatusLabel(
        canvas, 'BULL', Offset(rightStatsX, rightStatsY), Colors.grey);
    _drawStatusLabel(
        canvas, 'SHEL', Offset(rightStatsX, rightStatsY + 15), Colors.grey);
    _drawStatusLabel(
        canvas, 'RCKT', Offset(rightStatsX, rightStatsY + 30), Colors.grey);
    _drawStatusLabel(
        canvas, 'CELL', Offset(rightStatsX, rightStatsY + 45), Colors.grey);

    _drawStatusLabel(canvas, '80 / 200', Offset(rightStatsX + 50, rightStatsY),
        Colors.yellow);
    _drawStatusLabel(canvas, '0 / 50',
        Offset(rightStatsX + 50, rightStatsY + 15), Colors.yellow);
    _drawStatusLabel(canvas, '0 / 50',
        Offset(rightStatsX + 50, rightStatsY + 30), Colors.yellow);
    _drawStatusLabel(canvas, '0 / 300',
        Offset(rightStatsX + 50, rightStatsY + 45), Colors.yellow);
  }

  // Draw DOOM style pixelated numbers
  void _drawPixelatedNumber(
      Canvas canvas, String text, Offset position, Color color,
      {bool large = false}) {
    final fontSize = large ? 32.0 : 16.0;
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          letterSpacing: -1,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Draw drop shadow
    final TextPainter shadowPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          letterSpacing: -1,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    shadowPainter.layout();
    shadowPainter.paint(canvas, position.translate(2, 2));

    // Draw main text
    textPainter.paint(canvas, position);
  }

  // Draw status label text
  void _drawStatusLabel(
      Canvas canvas, String text, Offset position, Color color) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, position);
  }

  // Draw DOOM face based on health
  void _drawDoomFace(Canvas canvas, Rect rect, int health) {
    final Paint facePaint = Paint()
      ..color = const Color(0xFFFFC78F); // Skin tone

    // Draw base face
    canvas.drawRect(rect.deflate(2), facePaint);

    // Draw eyes
    final eyeWidth = rect.width * 0.15;
    final eyeHeight = rect.height * 0.15;
    final leftEyeRect = Rect.fromLTWH(
      rect.left + rect.width * 0.25 - eyeWidth / 2,
      rect.top + rect.height * 0.3 - eyeHeight / 2,
      eyeWidth,
      eyeHeight,
    );

    final rightEyeRect = Rect.fromLTWH(
      rect.left + rect.width * 0.75 - eyeWidth / 2,
      rect.top + rect.height * 0.3 - eyeHeight / 2,
      eyeWidth,
      eyeHeight,
    );

    // Eye expressions change based on health
    if (health > 75) {
      // Normal eyes
      canvas.drawRect(leftEyeRect, Paint()..color = Colors.black);
      canvas.drawRect(rightEyeRect, Paint()..color = Colors.black);

      // Happy mouth
      final mouthPath = Path();
      mouthPath.moveTo(
          rect.left + rect.width * 0.3, rect.top + rect.height * 0.7);
      mouthPath.lineTo(
          rect.left + rect.width * 0.45, rect.top + rect.height * 0.8);
      mouthPath.lineTo(
          rect.left + rect.width * 0.55, rect.top + rect.height * 0.8);
      mouthPath.lineTo(
          rect.left + rect.width * 0.7, rect.top + rect.height * 0.7);

      canvas.drawPath(
          mouthPath,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    } else if (health > 50) {
      // Concerned eyes
      canvas.drawRect(leftEyeRect, Paint()..color = Colors.black);
      canvas.drawRect(rightEyeRect, Paint()..color = Colors.black);

      // Neutral mouth
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + rect.width * 0.3,
          rect.top + rect.height * 0.75,
          rect.width * 0.4,
          rect.height * 0.05,
        ),
        Paint()..color = Colors.black,
      );
    } else if (health > 25) {
      // Hurt eyes (x shape)
      final leftEyePaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawLine(
        Offset(leftEyeRect.left, leftEyeRect.top),
        Offset(leftEyeRect.right, leftEyeRect.bottom),
        leftEyePaint,
      );

      canvas.drawLine(
        Offset(leftEyeRect.left, leftEyeRect.bottom),
        Offset(leftEyeRect.right, leftEyeRect.top),
        leftEyePaint,
      );

      canvas.drawLine(
        Offset(rightEyeRect.left, rightEyeRect.top),
        Offset(rightEyeRect.right, rightEyeRect.bottom),
        leftEyePaint,
      );

      canvas.drawLine(
        Offset(rightEyeRect.left, rightEyeRect.bottom),
        Offset(rightEyeRect.right, rightEyeRect.top),
        leftEyePaint,
      );

      // Grimace mouth
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + rect.width * 0.3,
          rect.top + rect.height * 0.75,
          rect.width * 0.4,
          rect.height * 0.1,
        ),
        Paint()..color = Colors.black,
      );

      // Blood drips
      final bloodPaint = Paint()..color = Colors.red.shade900;
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + rect.width * 0.4,
          rect.top + rect.height * 0.5,
          rect.width * 0.05,
          rect.height * 0.2,
        ),
        bloodPaint,
      );

      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + rect.width * 0.6,
          rect.top + rect.height * 0.45,
          rect.width * 0.05,
          rect.height * 0.15,
        ),
        bloodPaint,
      );
    } else {
      // Near death - red eyes
      canvas.drawRect(leftEyeRect, Paint()..color = Colors.red);
      canvas.drawRect(rightEyeRect, Paint()..color = Colors.red);

      // Grimace mouth with blood
      final mouthRect = Rect.fromLTWH(
        rect.left + rect.width * 0.25,
        rect.top + rect.height * 0.7,
        rect.width * 0.5,
        rect.height * 0.15,
      );

      canvas.drawRect(mouthRect, Paint()..color = Colors.red.shade900);

      // More blood drips
      final bloodPaint = Paint()..color = Colors.red.shade900;
      for (int i = 0; i < 5; i++) {
        final xPos = rect.left + rect.width * (0.3 + i * 0.1);
        final height = rect.height * (0.1 + i % 3 * 0.05);

        canvas.drawRect(
          Rect.fromLTWH(
            xPos,
            rect.top,
            rect.width * 0.05,
            height,
          ),
          bloodPaint,
        );
      }

      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + rect.width * 0.4,
          rect.top + rect.height * 0.5,
          rect.width * 0.05,
          rect.height * 0.2,
        ),
        bloodPaint,
      );

      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + rect.width * 0.6,
          rect.top + rect.height * 0.45,
          rect.width * 0.08,
          rect.height * 0.25,
        ),
        bloodPaint,
      );
    }
  }

  // Preload all sound effects
  Future<void> _preloadSoundEffects() async {
    try {
      // Get list of available sounds from our map
      final Map<String, String> availableSounds = {
        'shoot': 'Bullet Shot.mp3',
        'hit': 'Bullet Shot.mp3',
        'step': 'footstepMain.mp3',
        'collision': 'footstepMain.mp3',
      };

      // Preload each sound
      for (String soundFile in availableSounds.values.toSet()) {
        try {
          await FlameAudio.audioCache.load(soundFile);
          print('Loaded sound: $soundFile');
        } catch (e) {
          print('Failed to load sound $soundFile: $e');
        }
      }

      bulletSoundLoaded = true;
    } catch (e) {
      print('Error in sound preloading: $e');
      bulletSoundLoaded = false;
    }
  }

  // Play a sound effect safely with fallback
  void _playSoundEffect(String soundName, {double volume = 0.5}) {
    // List of available sounds
    final Map<String, String> availableSounds = {
      'shoot': 'Bullet Shot.mp3',
      'hit': 'Bullet Shot.mp3', // Reuse for hit sound
      'step': 'footstepMain.mp3',
      'collision': 'footstepMain.mp3', // Reuse for collision
    };

    // Check if the requested sound exists
    final String? soundFile = availableSounds[soundName];
    if (soundFile == null) {
      return; // No sound to play
    }

    // Try to play the sound
    try {
      FlameAudio.play(soundFile, volume: volume);
    } catch (e) {
      print('Error playing sound $soundName: $e');
    }
  }

  // Draw controls panel at the top of the screen
  void _drawControlsPanel(Canvas canvas, Vector2 size) {
    // Controls panel styling - DOOM style
    final panelHeight = 32.0;
    final panelWidth = size.x;

    // DOOM-style dark panel with slight transparency
    final panelPaint = Paint()..color = Color.fromRGBO(20, 20, 20, 0.85);

    // Red accent border like classic DOOM UI
    final borderPaint = Paint()
      ..color = Colors.red.shade900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw panel background
    final panelRect = Rect.fromLTWH(0, 0, panelWidth, panelHeight);
    canvas.drawRect(panelRect, panelPaint);

    // Draw bottom border only for that classic DOOM look
    canvas.drawLine(
      Offset(0, panelHeight),
      Offset(panelWidth, panelHeight),
      borderPaint,
    );

    // Controls text styling - pixelated look
    final TextStyle controlsStyle = TextStyle(
      color: Colors.grey.shade400,
      fontSize: 14,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.5, // Slightly spaced out like old games
      fontFamily: 'monospace', // Closest to pixelated look with system fonts
    );

    // Controls text content with DOOM-style capitalization
    final List<String> controls = [
      "MOVE: W/A/S/D",
      "TURN: ARROWS",
      "FIRE: SPACE/CLICK",
      "MUSIC: M",
      "CONTROLS: H"
    ];

    // Calculate spacing between controls
    final double spacing = panelWidth / controls.length;

    // Draw each control text
    for (int i = 0; i < controls.length; i++) {
      // Draw text with slight shadow for that 90s look
      final TextSpan shadowSpan = TextSpan(
        text: controls[i],
        style: controlsStyle.copyWith(
          color: Colors.black.withOpacity(0.8),
        ),
      );

      final TextPainter shadowPainter = TextPainter(
        text: shadowSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      shadowPainter.layout();

      // Draw shadow slightly offset
      final double xPosition =
          spacing * i + (spacing - shadowPainter.width) / 2;
      shadowPainter.paint(
          canvas,
          Offset(
              xPosition + 1, panelHeight / 2 - shadowPainter.height / 2 + 1));

      // Draw actual text
      final TextSpan controlSpan = TextSpan(
        text: controls[i],
        style: controlsStyle,
      );

      final TextPainter controlPainter = TextPainter(
        text: controlSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      controlPainter.layout();
      controlPainter.paint(canvas,
          Offset(xPosition, panelHeight / 2 - controlPainter.height / 2));

      // Add separator between controls except after the last one
      if (i < controls.length - 1) {
        final separatorPaint = Paint()
          ..color = Colors.red.shade900.withOpacity(0.6)
          ..strokeWidth = 1;

        canvas.drawLine(
          Offset(spacing * (i + 1), 6),
          Offset(spacing * (i + 1), panelHeight - 6),
          separatorPaint,
        );
      }
    }

    // Add status indicator in the corner if controls are pinned
    if (controlsAlwaysOn) {
      final pinIndicatorText = TextSpan(
        text: "PINNED",
        style: TextStyle(
          color: Colors.red.shade400,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );

      final pinPainter = TextPainter(
        text: pinIndicatorText,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
      );

      pinPainter.layout();
      pinPainter.paint(canvas, Offset(panelWidth - pinPainter.width - 5, 4));
    }
  }
}
