import 'package:flutter/material.dart';
import '../theme/exodo_theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const SplashScreen({
    super.key,
    required this.onFinished,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _exodoOpacity;
  late Animation<double> _exodoSlide;
  late Animation<double> _byBehaviorOpacity;
  late Animation<double> _byBehaviorSlide;
  late Animation<double> _glowScale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // 1. Logo behavior (animates from 0ms to 1000ms)
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    
    _logoScale = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
      ),
    );

    // 2. Exodo text (animates from 300ms to 1200ms)
    _exodoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.55, curve: Curves.easeOut),
      ),
    );

    _exodoSlide = Tween<double>(begin: 15.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    // 3. Ambient glow pulse (animates from 0ms to 2000ms)
    _glowScale = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeInOutSine),
      ),
    );

    // 4. By behavior text (animates from 800ms to 1800ms)
    _byBehaviorOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.8, curve: Curves.easeIn),
      ),
    );

    _byBehaviorSlide = Tween<double>(begin: 25.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    // Start animation and call onFinished when done
    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          widget.onFinished();
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ExodoColors.background,
      body: Stack(
        children: [
          // Ambient background glow centered behind the logo
          AnimatedBuilder(
            animation: _glowScale,
            builder: (context, child) {
              return Center(
                child: Container(
                  width: 350 * _glowScale.value,
                  height: 350 * _glowScale.value,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        ExodoColors.amberGlow,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          
          // Elements layout
          SafeArea(
            child: SizedBox.expand(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 36.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),
                    
                    // Top section: Logo + Exodo text
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Logo_behavior
                            Opacity(
                              opacity: _logoOpacity.value,
                              child: Transform.scale(
                                scale: _logoScale.value,
                                child: Image.asset(
                                  'assets/images/Logo_behavior.png',
                                  height: 110,
                                  color: ExodoColors.amber,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // exodo_text justo debajo de logo behavior
                            Opacity(
                              opacity: _exodoOpacity.value,
                              child: Transform.translate(
                                offset: Offset(0, _exodoSlide.value),
                                child: Image.asset(
                                  'assets/images/exodo_text.png',
                                  height: 64,
                                  color: ExodoColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    
                    const Spacer(flex: 4),
                    
                    // Bottom section: bybehavior_text
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _byBehaviorOpacity.value,
                          child: Transform.translate(
                            offset: Offset(0, _byBehaviorSlide.value),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/bybehavior_text.png',
                                  height: 42,
                                  color: ExodoColors.textPrimary,
                                ),
                                const SizedBox(height: 24),
                                // Sleek micro-loading indicator
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      ExodoColors.amber.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
