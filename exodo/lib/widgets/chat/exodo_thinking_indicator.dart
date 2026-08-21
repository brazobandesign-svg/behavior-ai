import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/exodo_theme.dart';

/// Indicador de Pensamiento / Razonamiento de Éxodo (Estilo Grok & AGY).
/// 
/// Características de diseño:
/// 1. Tres micro-esferas doradas/ámbar en onda sinusoidal continua y suave (Grok / AGY wave).
/// 2. Brillo radiante sutil (auras cálidas con difuminado suave).
/// 3. Cronómetro en vivo de precisión en segundos.
/// 4. Tipografía oficial de Anthropic (`AnthropicSans`) para una estética limpia y cohesiva.
class ExodoThinkingIndicator extends StatefulWidget {
  final Animation<double>? pulseAnim;

  const ExodoThinkingIndicator({
    super.key,
    this.pulseAnim,
  });

  @override
  State<ExodoThinkingIndicator> createState() => _ExodoThinkingIndicatorState();
}

class _ExodoThinkingIndicatorState extends State<ExodoThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Stopwatch _stopwatch;
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _stopwatch = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        final sec = (_stopwatch.elapsedMilliseconds / 1000).floor();
        if (sec != _elapsedSeconds) {
          setState(() {
            _elapsedSeconds = sec;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch.stop();
    _animCtrl.dispose();
    super.dispose();
  }

  String _getPhaseText(BuildContext context, int sec) {
    if (sec < 3) {
      return 'Razonando';
    } else if (sec < 6) {
      return 'Analizando contexto';
    } else {
      return 'Estructurando respuesta';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);
    final isLight = !isDarkMode && !isIncognito;
    final primaryColor = isLight ? const Color(0xFF2C2A28) : ExodoColors.amber;

    final phase = _getPhaseText(context, _elapsedSeconds);
    final displayText = '$phase · ${_elapsedSeconds}s';

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: AnimatedBuilder(
          animation: _animCtrl,
          builder: (context, child) {
            final progress = _animCtrl.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Puntos animados estilo Grok / AGY en Canvas
                SizedBox(
                  width: 28,
                  height: 18,
                  child: CustomPaint(
                    painter: GrokAgyDotsPainter(
                      progress: progress,
                      color: primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 2. Texto en tipografía AnthropicSans
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    displayText,
                    key: ValueKey<String>(displayText),
                    style: TextStyle(
                      fontFamily: 'AnthropicSans',
                      color: primaryColor.withValues(alpha: 0.85),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// ============================================================================
/// PAINTER: PUNTOS EN ONDA SINUSOIDAL FLUIDA (ESTILO GROK & AGY)
/// ============================================================================
class GrokAgyDotsPainter extends CustomPainter {
  final double progress;
  final Color color;

  GrokAgyDotsPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const int dotCount = 3;
    final double centerY = size.height / 2;
    final double spacing = size.width / (dotCount + 1);
    const double baseRadius = 2.4;
    const double waveAmplitude = 3.5;

    for (int i = 0; i < dotCount; i++) {
      final double cx = spacing * (i + 1);
      // Desfase armónico suave para cada punto (onda viajera)
      final double phase = (progress * 2 * math.pi) - (i * (math.pi / 2.2));
      final double sinVal = math.sin(phase);

      // Desplazamiento vertical en onda continua
      final double cy = centerY - (sinVal * waveAmplitude);

      // Escala y opacidad viva en función de la altura de la onda
      final double scale = 0.85 + (0.35 * ((sinVal + 1.0) / 2.0));
      final double opacity = (0.40 + (0.60 * ((sinVal + 1.0) / 2.0))).clamp(0.0, 1.0);
      final double currentRadius = baseRadius * scale;

      // 1. Aura / resplandor suave exterior
      final Paint glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacity * 0.35),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: currentRadius * 2.8),
        );
      canvas.drawCircle(Offset(cx, cy), currentRadius * 2.8, glowPaint);

      // 2. Núcleo brillante con gradiente radial cálido
      final Color coreLight = Color.lerp(color, Colors.white, 0.45)!;
      final Paint dotPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.25),
          radius: 0.85,
          colors: [
            coreLight.withValues(alpha: opacity),
            color.withValues(alpha: opacity),
          ],
        ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: currentRadius),
        );
      canvas.drawCircle(Offset(cx, cy), currentRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GrokAgyDotsPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
