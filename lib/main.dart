import 'package:flutter/material.dart';
import 'home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flame_audio/flame_audio.dart';

// Flag to track if audio has been initialized
bool audioInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only preload audio files, don't play them yet
  await _preloadAudioFiles();

  runApp(const MyApp());
}

// Preload audio files without playing them
Future<void> _preloadAudioFiles() async {
  try {
    print('Preloading audio files...');

    // Just preload the audio files but don't play them yet
    await FlameAudio.audioCache.loadAll(['backgroundMusic.mp3']);

    print('Audio files preloaded successfully');
  } catch (e) {
    print('Error preloading audio files: $e');
  }
}

// Initialize and play background music - call this after user interaction
Future<void> playBackgroundMusic() async {
  // Don't try to play if already initialized
  if (audioInitialized) return;

  try {
    print('Starting background music after user interaction...');

    // Play background music with BGM
    await FlameAudio.bgm.play('backgroundMusic.mp3', volume: 0.7);
    audioInitialized = true;

    print('Background music started successfully');
  } catch (e) {
    print('Error starting background music: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DOOM Flutter',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
        textTheme: ThemeData.dark().textTheme.apply(
              // Use a system monospace font instead of Orbitron to avoid font loading issues
              fontFamily: 'monospace',
            ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  late AnimationController _animationController;
  String? _username;
  bool _isOptionsOpen = false;
  int _difficulty = 1; // 0: Easy, 1: Medium, 2: Hard
  bool _isLoading = false;
  double _loadingProgress = 0.0;
  Timer? _loadingTimer;
  List<FlameParticle> _flameParticles = [];
  final int _numParticles = 50;
  final math.Random _random = math.Random();
  bool _hasInteracted = false;

  @override
  void initState() {
    super.initState();
    _loadUsername();

    // Setup animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // Initialize flame particles
    _initFlameParticles();

    // Start the flame animation timer
    Timer.periodic(const Duration(milliseconds: 50), (_) {
      _updateFlameParticles();
    });
  }

  void _initFlameParticles() {
    _flameParticles = List.generate(
        _numParticles,
        (_) => FlameParticle(
              x: _random.nextDouble() * 500,
              y: 700 + _random.nextDouble() * 100,
              vx: (_random.nextDouble() - 0.5) * 1.5,
              vy: -2 - _random.nextDouble() * 3,
              size: 5 + _random.nextDouble() * 20,
              life: 0.5 + _random.nextDouble() * 0.5,
            ));
  }

  void _updateFlameParticles() {
    if (!mounted) return;

    setState(() {
      for (var i = 0; i < _flameParticles.length; i++) {
        var particle = _flameParticles[i];

        // Update position
        particle.x += particle.vx;
        particle.y += particle.vy;

        // Update life
        particle.life -= 0.01;

        // Reset dead particles
        if (particle.life <= 0) {
          _flameParticles[i] = FlameParticle(
            x: _random.nextDouble() * 500,
            y: 700 + _random.nextDouble() * 100,
            vx: (_random.nextDouble() - 0.5) * 1.5,
            vy: -2 - _random.nextDouble() * 3,
            size: 5 + _random.nextDouble() * 20,
            life: 0.5 + _random.nextDouble() * 0.5,
          );
        }
      }
    });
  }

  void _handleFirstInteraction() {
    if (!_hasInteracted) {
      _hasInteracted = true;
      // Play music after first interaction
      playBackgroundMusic();
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _animationController.dispose();
    _loadingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('username');
      if (_username != null) {
        _usernameController.text = _username!;
      }
    });
  }

  Future<void> _saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
    setState(() {
      _username = username;
    });
  }

  Future<void> _saveDifficulty(int difficulty) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('difficulty', difficulty);
  }

  void _startLoading() {
    setState(() {
      _isLoading = true;
      _loadingProgress = 0.0;
    });

    _loadingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      setState(() {
        _loadingProgress += 0.02;
        if (_loadingProgress >= 1.0) {
          _loadingTimer?.cancel();
          _navigateToGame();
        }
      });
    });
  }

  void _navigateToGame() {
    final username = _usernameController.text.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HomePage(
          username: username,
          difficulty: _difficulty,
        ),
      ),
    );

    // Reset loading state after navigation
    setState(() {
      _isLoading = false;
      _loadingProgress = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return GestureDetector(
      // Capture any tap on the screen to start audio
      onTap: _handleFirstInteraction,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Animated background
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return CustomPaint(
                  size: Size(size.width, size.height),
                  painter: DoomBackgroundPainter(
                    animationValue: _animationController.value,
                  ),
                );
              },
            ),

            // Flame particles
            for (var particle in _flameParticles)
              Positioned(
                left: particle.x,
                top: particle.y,
                child: Opacity(
                  opacity: particle.life,
                  child: Container(
                    width: particle.size,
                    height: particle.size,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          Colors.yellow,
                          Colors.orange,
                          Colors.red.withOpacity(0.0),
                        ],
                        stops: const [0.0, 0.3, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(particle.size / 2),
                    ),
                  ),
                ),
              ),

            // Main content
            if (!_isOptionsOpen && !_isLoading) _buildMainScreen(size),
            if (_isOptionsOpen && !_isLoading) _buildOptionsScreen(size),
            if (_isLoading) _buildLoadingScreen(size),

            // DOOM logo at the top
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(
                child: _buildDoomLogo(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoomLogo() {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          colors: [
            Colors.red.shade800,
            Colors.yellow,
            Colors.red.shade800,
          ],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(bounds);
      },
      blendMode: BlendMode.srcATop,
      child: const Text(
        'DOOM FLUTTER',
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
          color: Colors.white,
          shadows: [
            Shadow(
              color: Colors.black,
              offset: Offset(3, 3),
              blurRadius: 5,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainScreen(Size size) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 100),

              // Metal plate with username input
              Container(
                width: 320,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.grey.shade600,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      spreadRadius: 1,
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  gradient: LinearGradient(
                    colors: [
                      Colors.grey.shade900,
                      Colors.grey.shade800,
                      Colors.grey.shade900,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'PLAYER NAME',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: Colors.red.shade800,
                          width: 2,
                        ),
                      ),
                      child: TextField(
                        controller: _usernameController,
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter your name',
                          hintStyle: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                        ),
                        textAlign: TextAlign.center,
                        onSubmitted: (value) {
                          if (value.isNotEmpty) {
                            _saveUsername(value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Game menu buttons with bloody style
              _buildBloodButton(
                'START GAME',
                onTap: () {
                  final username = _usernameController.text.trim();
                  if (username.isNotEmpty) {
                    _saveUsername(username);
                    _startLoading();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a username'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),

              const SizedBox(height: 20),

              _buildBloodButton(
                'OPTIONS',
                onTap: () {
                  setState(() {
                    _isOptionsOpen = true;
                  });
                },
              ),

              const SizedBox(height: 20),

              _buildBloodButton(
                'EXIT',
                onTap: () {
                  // Just for show, as we can't actually exit the web app
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cannot exit in web mode'),
                      backgroundColor: Colors.red,
                    ),
                  );
                },
              ),

              const SizedBox(height: 50),

              // Game instructions with flickering effect
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.7, end: 1.0),
                duration: const Duration(milliseconds: 1500),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Text(
                      'Use WASD or arrow keys to move\nSPACE or CLICK to shoot\nCollect health packs and ammo to survive',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red.withOpacity(0.8),
                        fontSize: 14,
                        shadows: [
                          Shadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 5,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBloodButton(String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        _handleFirstInteraction(); // Start music on button tap
        onTap();
      },
      child: Container(
        width: 300,
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.red.shade900,
              Colors.red.shade800,
              Colors.red.shade900,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.3),
              spreadRadius: 1,
              blurRadius: 15,
              offset: const Offset(0, 0),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Blood drip details
            CustomPaint(
              size: const Size(300, 60),
              painter: BloodDripPainter(),
            ),
            // Button label
            Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      offset: Offset(2, 2),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsScreen(Size size) {
    return Center(
      child: Container(
        width: 350,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.red.shade800, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.2),
              spreadRadius: 5,
              blurRadius: 15,
              offset: const Offset(0, 0),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  colors: [
                    Colors.red.shade800,
                    Colors.yellow,
                    Colors.red.shade800,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ).createShader(bounds);
              },
              child: const Text(
                'OPTIONS',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Difficulty options
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'DIFFICULTY:',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Difficulty selection
            Row(
              children: [
                _buildDoomDifficultyOption(0, 'Easy', 'Too Young to Die'),
                const SizedBox(width: 10),
                _buildDoomDifficultyOption(1, 'Medium', 'Hurt Me Plenty'),
                const SizedBox(width: 10),
                _buildDoomDifficultyOption(2, 'Hard', 'Nightmare!'),
              ],
            ),

            const SizedBox(height: 30),

            // Sound settings
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SOUND EFFECTS:',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: true, // Set based on actual preference
                  onChanged: (value) {
                    // TODO: Implement sound settings
                  },
                  activeColor: Colors.red.shade400,
                  activeTrackColor: Colors.red.shade800,
                ),
              ],
            ),

            const SizedBox(height: 30),

            // Back button
            GestureDetector(
              onTap: () {
                _saveDifficulty(_difficulty);
                setState(() {
                  _isOptionsOpen = false;
                });
              },
              child: Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.red.shade900,
                      Colors.red.shade800,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Center(
                  child: Text(
                    'BACK',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoomDifficultyOption(int level, String label, String doomName) {
    bool isSelected = _difficulty == level;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _difficulty = level;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: isSelected ? Colors.red.shade800 : Colors.grey.shade800,
            border: Border.all(
              color: isSelected ? Colors.red : Colors.grey.shade700,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade300,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                doomName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.yellow : Colors.grey.shade400,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen(Size size) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 100),

          const Text(
            'LOADING...',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.red,
              letterSpacing: 3,
              shadows: [
                Shadow(
                  color: Colors.black,
                  offset: Offset(3, 3),
                  blurRadius: 5,
                ),
              ],
            ),
          ),

          const SizedBox(height: 50),

          // Custom DOOM-style loading bar with blood filling
          Container(
            width: 350,
            height: 25,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(
                color: Colors.red.shade800,
                width: 2,
              ),
            ),
            child: Stack(
              children: [
                // Blood fill
                Container(
                  width: 350 * _loadingProgress,
                  height: 25,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.red.shade900,
                        Colors.red.shade600,
                        Colors.red.shade900,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),

                // Loading percentage text
                SizedBox(
                  width: 350,
                  child: Center(
                    child: Text(
                      '${(_loadingProgress * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            offset: Offset(1, 1),
                            blurRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // Random loading messages
          Text(
            _getRandomLoadingMessage(),
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  String _getRandomLoadingMessage() {
    final messages = [
      "Warming up BFG-9000...",
      "Spawning demons...",
      "Generating hell portals...",
      "Preparing chainsaw...",
      "Loading ammunition...",
      "Initializing demon AI...",
      "Unleashing the forces of hell...",
      "Counting ammo...",
      "Sharpening chainsaw teeth...",
      "Reloading shotgun..."
    ];

    return messages[_random.nextInt(messages.length)];
  }
}

class FlameParticle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  double life;

  FlameParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.life,
  });
}

class DoomBackgroundPainter extends CustomPainter {
  final double animationValue;
  final math.Random _random = math.Random();

  DoomBackgroundPainter({
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dark background
    final backgroundPaint = Paint()..color = Colors.black;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    // Draw animated grid lines
    final gridPaint = Paint()
      ..color = Colors.red.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Vertical lines
    final gridSize = 50.0;
    final xOffset = (animationValue * gridSize) % gridSize;
    for (double x = -xOffset; x < size.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }

    // Horizontal lines
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // Draw random pentagram symbols
    final pentagrams = 3;
    for (int i = 0; i < pentagrams; i++) {
      final x = _random.nextDouble() * size.width;
      final y = 300 + _random.nextDouble() * (size.height - 400);
      final radius = 40.0 + _random.nextDouble() * 20.0;

      final pentagramPaint = Paint()
        ..color = Colors.red.withOpacity(
            0.1 + (math.sin(animationValue * math.pi * 2 + i) + 1) / 10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      _drawPentagram(canvas, x, y, radius, pentagramPaint);
    }
  }

  void _drawPentagram(
      Canvas canvas, double x, double y, double radius, Paint paint) {
    final path = Path();
    final points = <Offset>[];

    for (int i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / 5;
      points.add(Offset(
        x + radius * math.cos(angle),
        y + radius * math.sin(angle),
      ));
    }

    // Connect in pentagram pattern: 0->2->4->1->3->0
    path.moveTo(points[0].dx, points[0].dy);
    path.lineTo(points[2].dx, points[2].dy);
    path.lineTo(points[4].dx, points[4].dy);
    path.lineTo(points[1].dx, points[1].dy);
    path.lineTo(points[3].dx, points[3].dy);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant DoomBackgroundPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

class BloodDripPainter extends CustomPainter {
  final math.Random _random = math.Random();

  @override
  void paint(Canvas canvas, Size size) {
    // Paint for blood drips
    final bloodPaint = Paint()
      ..color = Colors.red.shade900
      ..style = PaintingStyle.fill;

    // Add blood drips at the top
    final numDrips = 6 + _random.nextInt(4);
    for (int i = 0; i < numDrips; i++) {
      final x = _random.nextDouble() * size.width;
      final width = 5 + _random.nextDouble() * 10;
      final height = 5 + _random.nextDouble() * 15;

      // Drip shape
      final path = Path();
      path.moveTo(x, 0);
      path.quadraticBezierTo(
        x + width / 2,
        height / 2,
        x,
        height,
      );
      path.quadraticBezierTo(
        x - width / 2,
        height / 2,
        x,
        0,
      );

      canvas.drawPath(path, bloodPaint);
    }

    // Add blood drips at the bottom
    final numBottomDrips = 4 + _random.nextInt(3);
    for (int i = 0; i < numBottomDrips; i++) {
      final x = _random.nextDouble() * size.width;
      final width = 5 + _random.nextDouble() * 8;
      final height = 5 + _random.nextDouble() * 12;

      // Drip shape
      final path = Path();
      path.moveTo(x, size.height);
      path.quadraticBezierTo(
        x + width / 2,
        size.height - height / 2,
        x,
        size.height - height,
      );
      path.quadraticBezierTo(
        x - width / 2,
        size.height - height / 2,
        x,
        size.height,
      );

      canvas.drawPath(path, bloodPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
