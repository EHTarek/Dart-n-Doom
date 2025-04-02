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
      title: 'Dart\'n Doom',
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
    return Column(
      children: [
        // Main logo with flickering effect
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.8, end: 1.0),
          duration: const Duration(milliseconds: 500),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      Colors.red.shade900,
                      Colors.redAccent,
                      Colors.red.shade800,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ).createShader(bounds);
                },
                blendMode: BlendMode.srcATop,
                child: Stack(
                  children: [
                    // Shadow text for depth
                    Positioned(
                      left: 3,
                      top: 3,
                      child: Text(
                        'DART\'N DOOM',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Colors.black.withOpacity(0.7),
                        ),
                      ),
                    ),
                    // Main text
                    Text(
                      'DART\'N DOOM',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.red.shade800.withOpacity(0.7),
                            offset: const Offset(0, 0),
                            blurRadius: 10,
                          ),
                          Shadow(
                            color: Colors.black,
                            offset: const Offset(3, 3),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                    // Blood drips on logo
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 15,
                      child: CustomPaint(
                        painter: BloodDripPainter(dripsCount: 8, maxHeight: 15),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // Fighting game style "VS" section
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black,
                Colors.red.shade900.withOpacity(0.5),
                Colors.black,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'YOU',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.blue,
                      offset: Offset(0, 0),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade900,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      spreadRadius: 1,
                      blurRadius: 5,
                    ),
                  ],
                ),
                child: const Text(
                  'VS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'DEMONS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.red,
                      offset: Offset(0, 0),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.shade800,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.shade900.withOpacity(0.3),
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
                      'FIGHTER NAME',
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
                'ENTER BATTLE',
                onTap: () {
                  final username = _usernameController.text.trim();
                  if (username.isNotEmpty) {
                    _saveUsername(username);
                    _startLoading();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a fighter name'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),

              const SizedBox(height: 20),

              _buildBloodButton(
                'COMBAT OPTIONS',
                onTap: () {
                  setState(() {
                    _isOptionsOpen = true;
                  });
                },
              ),

              const SizedBox(height: 20),

              _buildBloodButton(
                'SURRENDER',
                onTap: () {
                  // Just for show, as we can't actually exit the web app
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Surrender is not an option!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                },
              ),

              const SizedBox(height: 30),

              // Game instructions with fighting game theme
              _buildGameInstructions(),
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
              color: Colors.red.withOpacity(0.5),
              spreadRadius: 2,
              blurRadius: 15,
              offset: const Offset(0, 0),
            ),
          ],
          border: Border.all(
            color: Colors.red.shade700,
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            // Blood drip details
            CustomPaint(
              size: const Size(300, 60),
              painter: BloodDripPainter(dripsCount: 10, maxHeight: 10),
            ),

            // Metallic shine effect
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 10,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.1),
                      Colors.white.withOpacity(0.05),
                      Colors.white.withOpacity(0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(5),
                    topRight: Radius.circular(5),
                  ),
                ),
              ),
            ),

            // Button label
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Battle symbol (optional)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CustomPaint(
                      painter: BattleSymbolPainter(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Button text
                  Text(
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
                  const SizedBox(width: 10),
                  // Mirror symbol on the right
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CustomPaint(
                      painter: BattleSymbolPainter(mirror: true),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // This method builds the instructions section with a fighting game theme
  Widget _buildGameInstructions() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        border: Border.all(
          color: Colors.red.shade900,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        children: [
          const Text(
            "BATTLE CONTROLS",
            style: TextStyle(
              color: Colors.red,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Movement controls
              _buildControlColumn(
                "MOVEMENT",
                ["W", "A/S/D", "ARROWS"],
                Icons.gamepad,
              ),
              const SizedBox(width: 30),
              // Attack controls
              _buildControlColumn(
                "ATTACKS",
                ["SPACE", "CLICK", "COLLECT POWER-UPS"],
                Icons.flash_on,
              ),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withOpacity(0.3),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              "DEFEAT ALL DEMONS TO ADVANCE",
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build control columns
  Widget _buildControlColumn(
      String title, List<String> controls, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.red.shade200,
          size: 20,
        ),
        const SizedBox(height: 5),
        Text(
          title,
          style: TextStyle(
            color: Colors.red.shade200,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        ...controls.map((control) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                control,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildLoadingScreen(Size size) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // VS animation
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            builder: (context, value, child) {
              return Transform.scale(
                scale: 1.0 + (1.0 - value) * 0.5,
                child: Opacity(
                  opacity: value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 15),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900,
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.7),
                          spreadRadius: 5,
                          blurRadius: 15,
                          offset: const Offset(0, 0),
                        ),
                      ],
                    ),
                    child: const Text(
                      'VS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 50),

          // Loading bar with demonic theme
          SizedBox(
            width: 300,
            child: Column(
              children: [
                // Player vs enemies display
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Player display
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade800,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: Colors.blue.shade200,
                              width: 2,
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              'P',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _usernameController.text.isEmpty
                              ? 'FIGHTER'
                              : _usernameController.text.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    // Enemies display
                    Row(
                      children: [
                        Text(
                          'HELLSPAWN',
                          style: TextStyle(
                            color: Colors.red.shade300,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.red.shade900,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: Colors.red.shade300,
                              width: 2,
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              'E',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Loading progress
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      // Blood container
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),

                      // Progress indicator
                      Container(
                        height: 20,
                        width: 300 * _loadingProgress,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.shade900,
                              Colors.red.shade700,
                              Colors.red.shade900,
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _loadingProgress > 0.05
                              ? Container(
                                  width: 30,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.red.shade900.withOpacity(0.0),
                                        Colors.red.shade200.withOpacity(0.8),
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Loading message
                Text(
                  _getRandomLoadingMessage(),
                  style: TextStyle(
                    color: Colors.red.shade400,
                    fontSize: 16,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
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
            // Title with flaming effect
            Stack(
              children: [
                // Flames behind title
                SizedBox(
                  height: 50,
                  child: CustomPaint(
                    painter: FlamesPainter(),
                    size: const Size(300, 40),
                  ),
                ),
                // Title text
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
                    'COMBAT OPTIONS',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            // Difficulty options
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.red.shade900,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'COMBAT DIFFICULTY:',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 15),

                  // Difficulty selection
                  Row(
                    children: [
                      _buildDoomDifficultyOption(0, 'Easy', 'ROOKIE'),
                      const SizedBox(width: 10),
                      _buildDoomDifficultyOption(1, 'Medium', 'VETERAN'),
                      const SizedBox(width: 10),
                      _buildDoomDifficultyOption(2, 'Hard', 'SLAYER'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Sound settings
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.red.shade900,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'BATTLE SOUNDS:',
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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      spreadRadius: 1,
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_back_ios,
                        color: Colors.red.shade200,
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'RETURN TO BATTLE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoomDifficultyOption(
      int level, String label, String difficultyName) {
    final isSelected = _difficulty == level;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _difficulty = level;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      Colors.red.shade900,
                      Colors.red.shade800,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : LinearGradient(
                    colors: [
                      Colors.grey.shade800,
                      Colors.grey.shade900,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? Colors.red.shade400 : Colors.grey.shade700,
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      spreadRadius: 1,
                      blurRadius: 5,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Text(
                difficultyName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade400,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: Colors.red.shade200,
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRandomLoadingMessage() {
    final messages = [
      "Summoning hellish enemies...",
      "Sharpening combat blades...",
      "Preparing battle arena...",
      "Loading demonic textures...",
      "Arming combat systems...",
      "Calculating damage modifiers...",
      "Calibrating weapons...",
      "Initializing combat AI...",
      "Opening portal to hell...",
      "Preparing your resurrection stone..."
    ];

    return messages[_random.nextInt(messages.length)];
  }
}

class FlamesPainter extends CustomPainter {
  final math.Random _random = math.Random();

  @override
  void paint(Canvas canvas, Size size) {
    final int flameCount = 15;

    for (int i = 0; i < flameCount; i++) {
      final double x = size.width * i / flameCount;
      final double height = 10 + _random.nextDouble() * 20;

      final path = Path();
      path.moveTo(x, size.height);

      // Create flame shape with bezier curves
      path.cubicTo(x - 5, size.height - height / 3, x + 5,
          size.height - height * 2 / 3, x, size.height - height);

      path.cubicTo(x - 5, size.height - height * 2 / 3, x + 5,
          size.height - height / 3, x, size.height);

      // Create gradient for flame
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.yellow,
            Colors.orange,
            Colors.red.shade900,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(
            Rect.fromLTRB(x - 10, size.height - height, x + 10, size.height));

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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
    // Draw dark gradient background
    final Rect rect = Offset.zero & size;
    final Paint paint = Paint();

    // Darker, more ominous gradient
    final Gradient gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF000000),
        const Color(0xFF1A0000),
        const Color(0xFF290000),
      ],
    );

    paint.shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);

    // Draw blood splatters in the background
    final bloodPaint = Paint()..color = Colors.red.shade900.withOpacity(0.2);

    // Generate blood splatters based on animation value
    final int numSplatters = 20;
    for (int i = 0; i < numSplatters; i++) {
      final double x = _random.nextDouble() * size.width;
      final double y = _random.nextDouble() * size.height;

      // Vary the size and opacity based on animation
      final double splatterSize = 5.0 + 20.0 * _random.nextDouble();
      final double opacity = 0.1 + 0.3 * _random.nextDouble();

      bloodPaint.color = Colors.red.shade900.withOpacity(opacity);

      canvas.drawCircle(
        Offset(x, y),
        splatterSize,
        bloodPaint,
      );

      // Add drip effect to some splatters
      if (_random.nextBool()) {
        final path = Path();
        path.moveTo(x, y);

        final double dripLength = 10.0 + 30.0 * _random.nextDouble();
        final double controlX = x + (5.0 - 10.0 * _random.nextDouble());

        path.quadraticBezierTo(controlX, y + dripLength / 2, x, y + dripLength);

        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.red.shade900.withOpacity(opacity * 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 + 3.0 * _random.nextDouble(),
        );
      }
    }

    // Add demonic symbols or glyphs occasionally
    if (animationValue > 0.8) {
      final demonicPaint = Paint()
        ..color = Colors.red.shade700.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Simple pentagram
      final double centerX = size.width * 0.25;
      final double centerY = size.height * 0.7;
      final double radius = 50.0;

      final Path pentagram = Path();

      for (int i = 0; i < 5; i++) {
        final double angle = (i * 144) * math.pi / 180;
        final double x = centerX + radius * math.cos(angle);
        final double y = centerY + radius * math.sin(angle);

        if (i == 0) {
          pentagram.moveTo(x, y);
        } else {
          pentagram.lineTo(x, y);
        }
      }
      pentagram.close();

      canvas.drawPath(pentagram, demonicPaint);
    }
  }

  @override
  bool shouldRepaint(DoomBackgroundPainter oldDelegate) => true;
}

class BloodDripPainter extends CustomPainter {
  final int dripsCount;
  final double maxHeight;
  final math.Random _random = math.Random();

  BloodDripPainter({this.dripsCount = 5, this.maxHeight = 20});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.red.shade900
      ..style = PaintingStyle.fill;

    // Create blood drip effect
    for (int i = 0; i < dripsCount; i++) {
      final double x = size.width * i / (dripsCount - 1);
      final double height = _random.nextDouble() * maxHeight;
      final double width = 4 + _random.nextDouble() * 6;

      final Path path = Path();
      path.moveTo(x - width / 2, 0);
      path.quadraticBezierTo(
        x,
        height / 2,
        x,
        height,
      );
      path.quadraticBezierTo(
        x,
        height / 2,
        x + width / 2,
        0,
      );
      path.close();

      canvas.drawPath(path, paint);
    }

    // Add additional splatters
    for (int i = 0; i < dripsCount ~/ 2; i++) {
      final double x = _random.nextDouble() * size.width;
      final double y = _random.nextDouble() * size.height;
      final double radius = 1 + _random.nextDouble() * 3;

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(BloodDripPainter oldDelegate) => false;
}

// Small battle symbol for buttons
class BattleSymbolPainter extends CustomPainter {
  final bool mirror;

  BattleSymbolPainter({this.mirror = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path();

    if (mirror) {
      // Mirrored sword/dagger symbol
      path.moveTo(size.width, size.height / 2);
      path.lineTo(0, size.height / 2);
      path.moveTo(size.width * 0.3, size.height * 0.3);
      path.lineTo(0, size.height / 2);
      path.lineTo(size.width * 0.3, size.height * 0.7);
    } else {
      // Sword/dagger symbol
      path.moveTo(0, size.height / 2);
      path.lineTo(size.width, size.height / 2);
      path.moveTo(size.width * 0.7, size.height * 0.3);
      path.lineTo(size.width, size.height / 2);
      path.lineTo(size.width * 0.7, size.height * 0.7);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(BattleSymbolPainter oldDelegate) => false;
}
