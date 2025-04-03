import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PlatformHelper {
  // Check if the current platform is mobile (iOS or Android)
  static bool isMobile(BuildContext context) {
    return Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.android;
  }

  // Check if device should show mobile controls (either on mobile platform OR in small window on any platform)
  static bool shouldShowMobileControls(BuildContext context) {
    // Always show mobile controls on actual mobile devices
    if (isMobile(context)) return true;

    // Show mobile controls on any platform if the window is small enough (like mobile view)
    final size = MediaQuery.of(context).size;
    return size.width < 600 || size.height < 500;
  }
}
