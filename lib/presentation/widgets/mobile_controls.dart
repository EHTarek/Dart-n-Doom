import 'package:flutter/material.dart';
import '../../core/util/platform_helper.dart';

class MobileControls extends StatefulWidget {
  // Callbacks for control actions
  final Function(double dx, double dy) onMove;
  final Function() onAttack;
  final Function() onAttackEnd;

  const MobileControls({
    Key? key,
    required this.onMove,
    required this.onAttack,
    required this.onAttackEnd,
  }) : super(key: key);

  @override
  State<MobileControls> createState() => _MobileControlsState();
}

class _MobileControlsState extends State<MobileControls> {
  // Joystick state
  bool _joystickInUse = false;
  Offset _joystickPosition = Offset.zero;
  Offset _joystickDelta = Offset.zero;
  final double _joystickRadius = 60.0;
  final double _innerJoystickRadius = 30.0;

  // Attack button state
  bool _attackPressed = false;

  @override
  Widget build(BuildContext context) {
    // Only show controls on mobile devices or small windows
    if (!PlatformHelper.shouldShowMobileControls(context)) {
      return const SizedBox.shrink();
    }

    // Get screen size to position controls appropriately
    final size = MediaQuery.of(context).size;

    return Stack(
      children: [
        // Movement joystick (bottom left)
        Positioned(
          left: size.width * 0.05,
          bottom: size.height * 0.08,
          child: _buildJoystick(),
        ),

        // Attack button (bottom right)
        Positioned(
          right: size.width * 0.05,
          bottom: size.height * 0.08,
          child: _buildAttackButton(),
        ),
      ],
    );
  }

  // Build the joystick control
  Widget _buildJoystick() {
    return GestureDetector(
      onPanStart: _onJoystickStart,
      onPanUpdate: _onJoystickUpdate,
      onPanEnd: _onJoystickEnd,
      child: Container(
        width: _joystickRadius * 2,
        height: _joystickRadius * 2,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30, width: 2),
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            width: _innerJoystickRadius * 2,
            height: _innerJoystickRadius * 2,
            transform: Matrix4.translationValues(
              _joystickDelta.dx,
              _joystickDelta.dy,
              0,
            ),
            decoration: BoxDecoration(
              color: _joystickInUse ? Colors.white70 : Colors.white38,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  // Build the attack button
  Widget _buildAttackButton() {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _attackPressed = true;
        });
        widget.onAttack();
      },
      onTapUp: (_) {
        setState(() {
          _attackPressed = false;
        });
        widget.onAttackEnd();
      },
      onTapCancel: () {
        setState(() {
          _attackPressed = false;
        });
        widget.onAttackEnd();
      },
      child: Container(
        width: _joystickRadius * 2,
        height: _joystickRadius * 2,
        decoration: BoxDecoration(
          color: _attackPressed
              ? Colors.red.withOpacity(0.8)
              : Colors.red.withOpacity(0.5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30, width: 2),
        ),
        child: const Center(
          child: Icon(
            Icons.flash_on,
            color: Colors.white,
            size: 36,
          ),
        ),
      ),
    );
  }

  // Joystick gesture handlers
  void _onJoystickStart(DragStartDetails details) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localOffset = box.globalToLocal(details.globalPosition);

    setState(() {
      _joystickInUse = true;
      _joystickPosition = localOffset;
    });
  }

  void _onJoystickUpdate(DragUpdateDetails details) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localOffset = box.globalToLocal(details.globalPosition);

    // Calculate delta from joystick center
    Offset delta = localOffset - _joystickPosition;

    // Limit delta to joystick radius
    double distance = delta.distance;
    if (distance > _joystickRadius) {
      delta = delta * (_joystickRadius / distance);
    }

    // Normalize for input (values between -1 and 1)
    double dx = delta.dx / _joystickRadius;
    double dy = delta.dy / _joystickRadius;

    setState(() {
      _joystickDelta = delta;
    });

    // Send movement input
    widget.onMove(dx, dy);
  }

  void _onJoystickEnd(DragEndDetails details) {
    setState(() {
      _joystickInUse = false;
      _joystickDelta = Offset.zero;
    });

    // Reset movement
    widget.onMove(0, 0);
  }
}
