import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/a11y.dart';
import '../utils/theme_provider.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;
  const SplashScreen({super.key, required this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _navTimer;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();

    // Preload Google Fonts during splash screen to avoid FOUT later
    _preloadFonts();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-navigate after splash duration
    _navTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => widget.nextScreen,
            transitionsBuilder: (_, a, __, child) => FadeTransition(
              opacity: a,
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  /// Trigger Google Fonts download during splash so screens don't flicker.
  Future<void> _preloadFonts() async {
    try {
      // Request all font families used in the app
      GoogleFonts.dmSans();
      GoogleFonts.rajdhani();
      GoogleFonts.exo2();
      // Wait for pending font downloads to complete
      await GoogleFonts.pendingFonts();
    } catch (_) {
      // Font loading errors are non-critical — silently ignore
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = reducedMotion(context);
    if (!_reduced) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Animated icon container with pulse
              if (_reduced)
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Center(
                    child: Text(
                      '🎓',
                      style: TextStyle(fontSize: 44),
                    ),
                  ),
                )
              else
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Center(
                      child: Text(
                        '🎓',
                        style: TextStyle(fontSize: 44),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 28),

              // App title
              Text(
                'CST',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: c.white,
                  height: 1.0,
                ),
              )
                  .animate()
                  .fadeIn(duration: _reduced ? 0.ms : 600.ms, delay: _reduced ? 0.ms : 200.ms, curve: Curves.easeOut)
                  .slideY(begin: _reduced ? 0 : 20, end: 0, duration: _reduced ? 0.ms : 600.ms, delay: _reduced ? 0.ms : 200.ms, curve: Curves.easeOutBack),

              const SizedBox(height: 4),

              Text(
                'Department Portal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.accent,
                ),
              )
                  .animate()
                  .fadeIn(duration: _reduced ? 0.ms : 600.ms, delay: _reduced ? 0.ms : 350.ms, curve: Curves.easeOut)
                  .slideY(begin: _reduced ? 0 : 16, end: 0, duration: _reduced ? 0.ms : 600.ms, delay: _reduced ? 0.ms : 350.ms, curve: Curves.easeOut),

              const SizedBox(height: 48),

              // Subtitle
              Text(
                'Computer Science & Technology',
                style: TextStyle(
                  fontSize: 13,
                  color: c.muted,
                ),
              )
                  .animate()
                  .fadeIn(duration: _reduced ? 0.ms : 400.ms, delay: _reduced ? 0.ms : 500.ms, curve: Curves.easeOut)
                  .slideY(begin: _reduced ? 0 : 10, end: 0, duration: _reduced ? 0.ms : 400.ms, delay: _reduced ? 0.ms : 500.ms, curve: Curves.easeOut),

              const Spacer(flex: 1),

              // Loading indicator
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: c.accent.withValues(alpha: 0.6),
                ),
              )
                  .animate()
                  .fadeIn(duration: _reduced ? 0.ms : 800.ms, delay: _reduced ? 0.ms : 600.ms)
                  .shimmer(duration: _reduced ? 0.ms : 1200.ms, color: c.white.withValues(alpha: 0.15)),

              const SizedBox(height: 8),

              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 11,
                  color: c.muted.withValues(alpha: 0.6),
                ),
              )
                  .animate()
                  .fadeIn(duration: _reduced ? 0.ms : 800.ms, delay: _reduced ? 0.ms : 700.ms),

              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
