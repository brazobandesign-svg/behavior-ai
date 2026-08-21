import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/exodo_theme.dart';

/// Tipos de animaciones 100% en código para el estado de razonamiento de Éxodo.
enum ThinkingAnimationType {
  gyroscope,     // 1. Giróscopo Cuántico (Órbitas Armónicas)
  spark,         // 2. Chispa Geométrica Viva (Breathing Spark)
  harmonicWave,  // 3. Ondas de Frecuencia Armónica (Sinusoid Rings)
}

/// Estado global o temporal del tipo de animación activo (permite ciclar al tocar).
ThinkingAnimationType _activeThinkingType = ThinkingAnimationType.spark;

ThinkingAnimationType get activeThinkingType => _activeThinkingType;
void setActiveThinkingType(ThinkingAnimationType type) {
  _activeThinkingType = type;
}

/// Indicador de Pensamiento / Razonamiento de Éxodo.
/// Integra:
/// 1. Animación matemática en Canvas/CustomPainter (cero assets de imagen).
/// 2. Cronómetro de precisión en segundos en tiempo real (1s, 2s, 3s...).
/// 3. Transición de fases cognitivas suaves (Razonando -> Analizando contexto -> Estructurando).
/// 4. Tap para ciclar y probar estilos en vivo en pantalla.
class ExodoThinkingIndicator extends StatefulWidget {
  final Animation<double>? pulseAnim;
  final ThinkingAnimationType? forceType;

  const ExodoThinkingIndicator({
    super.key,
    this.pulseAnim,
    this.forceType,
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
      duration: const Duration(milliseconds: 2400),
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

  void _cycleType(BuildContext context) {
    final appState = context.read<AppState>();
    appState.setThinkingAnimationIndex(appState.thinkingAnimationIndex + 1);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);
    final isLight = !isDarkMode && !isIncognito;
    final primaryColor = isLight ? const Color(0xFF1E1E1E) : ExodoColors.amber;
    final animIdx = context.select<AppState, int>((s) => s.thinkingAnimationIndex);
    final currentType = widget.forceType ?? ThinkingAnimationType.values[animIdx % ThinkingAnimationType.values.length];

    final phase = _getPhaseText(context, _elapsedSeconds);
    final displayText = '$phase · ${_elapsedSeconds}s';

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _cycleType(context),
        onLongPress: () => showThinkingStylesShowcase(context),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: AnimatedBuilder(
            animation: _animCtrl,
            builder: (context, child) {
              final progress = _animCtrl.value;
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Icono animado generado 100% en Canvas
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CustomPaint(
                      painter: _buildPainter(currentType, progress, primaryColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 2. Fases de texto dinámicas con contador en vivo
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Text(
                      displayText,
                      key: ValueKey<String>(displayText),
                      style: GoogleFonts.inter(
                        color: primaryColor.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  CustomPainter _buildPainter(
    ThinkingAnimationType type,
    double progress,
    Color color,
  ) {
    switch (type) {
      case ThinkingAnimationType.gyroscope:
        return QuantumGyroscopePainter(progress: progress, color: color);
      case ThinkingAnimationType.spark:
        return GeometricSparkPainter(progress: progress, color: color);
      case ThinkingAnimationType.harmonicWave:
        return HarmonicWavePainter(progress: progress, color: color);
    }
  }
}

/// ============================================================================
/// 1. PAINTER: GIRÓSCOPO CUÁNTICO (ÓRBITAS ARMÓNICAS)
/// ============================================================================
class QuantumGyroscopePainter extends CustomPainter {
  final double progress;
  final Color color;

  QuantumGyroscopePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.44;

    // Núcleo central pulsante
    final pulse = 0.5 + (0.5 * math.sin(progress * 2 * math.pi));
    final corePaint = Paint()
      ..color = color.withValues(alpha: 0.5 + (0.5 * pulse))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 2.2 + (1.2 * pulse), corePaint);

    // Glow suave del núcleo
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.2 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center, 5.0 * pulse, glowPaint);

    // Órbita 1 (Rotación horaria)
    final angle1 = progress * 2 * math.pi;
    final ringPaint1 = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle1);
    final rect1 = Rect.fromCenter(
      center: Offset.zero,
      width: radius * 2,
      height: radius * 0.9,
    );
    canvas.drawOval(rect1, ringPaint1);

    // Partícula en órbita 1
    final particle1 = Offset(radius * math.cos(angle1), (radius * 0.45) * math.sin(angle1));
    final dotPaint1 = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(particle1, 2.0, dotPaint1);
    canvas.restore();

    // Órbita 2 (Rotación anti-horaria inclinada)
    final angle2 = -progress * 2 * math.pi * 1.3;
    final ringPaint2 = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle2 + (math.pi / 4));
    final rect2 = Rect.fromCenter(
      center: Offset.zero,
      width: radius * 1.8,
      height: radius * 0.8,
    );
    canvas.drawOval(rect2, ringPaint2);

    // Partícula en órbita 2
    final particle2 = Offset((radius * 0.9) * math.cos(angle2), (radius * 0.4) * math.sin(angle2));
    canvas.drawCircle(particle2, 1.8, dotPaint1);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant QuantumGyroscopePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// ============================================================================
/// 2. PAINTER: CHISPA GEOMÉTRICA VIVA (BREATHING SPARK)
/// ============================================================================
class GeometricSparkPainter extends CustomPainter {
  final double progress;
  final Color color;

  GeometricSparkPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width * 0.48;

    // Respiración armónica de escala y rotación lenta
    final breath = 0.85 + (0.25 * math.sin(progress * 2 * math.pi));
    final currentR = maxR * breath;
    final innerR = currentR * 0.28;
    final rotAngle = progress * 2 * math.pi * 0.4; // rotación sutil

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotAngle);

    // Construcción de estrella geométrica de 4 puntas con curvas cóncavas
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final aOuter = (i * math.pi / 2);
      final aInner = aOuter + (math.pi / 4);

      final pOuter = Offset(currentR * math.cos(aOuter), currentR * math.sin(aOuter));
      final pInner = Offset(innerR * math.cos(aInner), innerR * math.sin(aInner));

      if (i == 0) {
        path.moveTo(pOuter.dx, pOuter.dy);
      } else {
        path.lineTo(pOuter.dx, pOuter.dy);
      }
      path.quadraticBezierTo(0, 0, pInner.dx, pInner.dy);
    }
    path.close();

    // Relleno con gradiente dorado
    final fillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.9),
          color.withValues(alpha: 0.4),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: currentR))
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Contorno fino
    final strokePaint = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, strokePaint);

    // Micro destellos en los 4 vértices
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8 * breath)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 4; i++) {
      final a = (i * math.pi / 2);
      final tip = Offset(currentR * math.cos(a), currentR * math.sin(a));
      canvas.drawCircle(tip, 1.2, dotPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GeometricSparkPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// ============================================================================
/// 3. PAINTER: ONDAS DE FRECUENCIA ARMÓNICA (SINUSOID RINGS)
/// ============================================================================
class HarmonicWavePainter extends CustomPainter {
  final double progress;
  final Color color;

  HarmonicWavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.38;

    // Onda 1 exterior
    _drawWaveRing(
      canvas,
      center,
      baseRadius: baseRadius,
      waveCount: 4,
      amplitude: 2.2,
      phase: progress * 2 * math.pi * 2,
      paint: Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    // Onda 2 interior
    _drawWaveRing(
      canvas,
      center,
      baseRadius: baseRadius * 0.65,
      waveCount: 3,
      amplitude: 1.6,
      phase: -progress * 2 * math.pi * 1.5,
      paint: Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    // Punto central armónico
    final centerPulse = 0.5 + (0.5 * math.sin(progress * 2 * math.pi * 3));
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.7 + (0.3 * centerPulse))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 2.0, dotPaint);
  }

  void _drawWaveRing(
    Canvas canvas,
    Offset center, {
    required double baseRadius,
    required int waveCount,
    required double amplitude,
    required double phase,
    required Paint paint,
  }) {
    final path = Path();
    const int segments = 60;
    for (int i = 0; i <= segments; i++) {
      final theta = (i / segments) * 2 * math.pi;
      final r = baseRadius + (amplitude * math.sin((waveCount * theta) + phase));
      final x = center.dx + (r * math.cos(theta));
      final y = center.dy + (r * math.sin(theta));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant HarmonicWavePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// ============================================================================
/// SHOWCASE MODAL: Muestra los 3 estilos en vivo lado a lado para compararlos
/// ============================================================================
void showThinkingStylesShowcase(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF141416),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _ThinkingStylesShowcaseSheet(),
  );
}

class _ThinkingStylesShowcaseSheet extends StatefulWidget {
  const _ThinkingStylesShowcaseSheet();

  @override
  State<_ThinkingStylesShowcaseSheet> createState() => _ThinkingStylesShowcaseSheetState();
}

class _ThinkingStylesShowcaseSheetState extends State<_ThinkingStylesShowcaseSheet> {
  @override
  Widget build(BuildContext context) {
    final types = [
      (
        ThinkingAnimationType.gyroscope,
        '1. Giróscopo Cuántico',
        'Órbitas armónicas concéntricas con partículas en rotación opuesta y núcleo de luz.',
      ),
      (
        ThinkingAnimationType.spark,
        '2. Chispa Geométrica Viva',
        'Estrella matemática de 4 puntas con respiración suave, rotación y destellos en vértices.',
      ),
      (
        ThinkingAnimationType.harmonicWave,
        '3. Ondas de Frecuencia Armónica',
        'Anillos sinusoidales modulados con funciones trigonométricas y pulso vivo.',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: ExodoColors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Estilos de Animación de Razonamiento',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Animaciones 100% generadas por código (Canvas / CustomPainter a 120 FPS). Toca una opción para seleccionarla.',
              style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white60),
            ),
            const SizedBox(height: 18),
            for (final item in types) ...[
              _buildStyleOptionCard(item.$1, item.$2, item.$3),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStyleOptionCard(
    ThinkingAnimationType type,
    String title,
    String description,
  ) {
    final currentIdx = context.watch<AppState>().thinkingAnimationIndex;
    final isSelected = currentIdx == type.index;

    return InkWell(
      onTap: () {
        context.read<AppState>().setThinkingAnimationIndex(type.index);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF221F1A) : const Color(0xFF1B1B1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? ExodoColors.amber : Colors.white10,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            _ThinkingDemoBadge(type: type),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? ExodoColors.amber : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: ExodoColors.amber, size: 20)
            else
              const Icon(Icons.radio_button_unchecked, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ThinkingDemoBadge extends StatefulWidget {
  final ThinkingAnimationType type;
  const _ThinkingDemoBadge({required this.type});

  @override
  State<_ThinkingDemoBadge> createState() => _ThinkingDemoBadgeState();
}

class _ThinkingDemoBadgeState extends State<_ThinkingDemoBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        CustomPainter painter;
        switch (widget.type) {
          case ThinkingAnimationType.gyroscope:
            painter = QuantumGyroscopePainter(
              progress: _ctrl.value,
              color: ExodoColors.amber,
            );
            break;
          case ThinkingAnimationType.spark:
            painter = GeometricSparkPainter(
              progress: _ctrl.value,
              color: ExodoColors.amber,
            );
            break;
          case ThinkingAnimationType.harmonicWave:
            painter = HarmonicWavePainter(
              progress: _ctrl.value,
              color: ExodoColors.amber,
            );
            break;
        }
        return SizedBox(
          width: 32,
          height: 32,
          child: CustomPaint(painter: painter),
        );
      },
    );
  }
}
