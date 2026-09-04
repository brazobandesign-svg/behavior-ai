import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_i18n.dart';
import '../../services/app_state.dart';
import '../../theme/exodo_theme.dart';

/// Indicador de Pensamiento de Éxodo: 2 animaciones de 4 puntos elegidas
/// al azar por episodio (intercambio l46 / esquinas l38), color neutro
/// (yeso en dark, #252525 en light, igual que los textos) + cronómetro.
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
  // Variante elegida al azar al montar (una por episodio de pensamiento).
  late final bool _shuffle;

  @override
  void initState() {
    super.initState();
    _shuffle = math.Random().nextBool();
    _animCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _shuffle ? 1000 : 500),
    )..repeat();

    _stopwatch = Stopwatch()..start();
    // P3 batería: el display muestra segundos enteros; con 1s de periodo el
    // isolate despierta 10 veces menos que antes (100ms) sin pérdida visual.
    _timer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
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
    final t = AppI18n.of(context).t;
    if (sec < 3) {
      return t('thinking.phase_1');
    } else if (sec < 6) {
      return t('thinking.phase_2');
    } else {
      return t('thinking.phase_3');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);
    final isLight = !isDarkMode && !isIncognito;
    // Neutro igual que los textos: yeso en dark, #252525 en light.
    final neutral = isLight ? const Color(0xFF252525) : ExodoColors.textPrimary;

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
                // 1. Loader de 4 puntos (~alto del texto), variante al azar.
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CustomPaint(
                    painter: _FourDotsPainter(
                      progress: progress,
                      shuffle: _shuffle,
                      color: neutral,
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
                      color: neutral.withValues(alpha: 0.85),
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
/// PAINTER: 4 PUNTOS, 2 PATRONES (l46 intercambio / l38 esquinas)
/// ============================================================================
class _FourDotsPainter extends CustomPainter {
  final double progress;
  final bool shuffle;
  final Color color;

  _FourDotsPainter({
    required this.progress,
    required this.shuffle,
    required this.color,
  });

  // Esquinas del grid unitario: TL, TR, BR, BL.
  static const _corners = [
    Offset(0.2, 0.2),
    Offset(0.8, 0.2),
    Offset(0.8, 0.8),
    Offset(0.2, 0.8),
  ];

  /// Permutación de cada punto según keyframes CSS (l46: 0% / 45% / 95%).
  List<Offset> _shuffleStops(double t) {
    // P0: dot0 TL, dot1 TR, dot2 BR, dot3 BL
    // P1: dot0 BR, dot1 TR, dot2 TL, dot3 BL
    // P2: dot0 BR, dot1 BL, dot2 TL, dot3 TR
    const p0 = [0, 1, 2, 3];
    const p1 = [2, 1, 0, 3];
    const p2 = [2, 3, 0, 1];
    List<int> from, to;
    double f;
    if (t < 0.45) {
      from = p0;
      to = p1;
      f = t / 0.45;
    } else if (t < 0.95) {
      from = p1;
      to = p2;
      f = (t - 0.45) / 0.5;
    } else {
      from = p2;
      to = p0;
      f = (t - 0.95) / 0.05;
    }
    f = f.clamp(0.0, 1.0);
    return List<Offset>.generate(
      4,
      (i) => Offset.lerp(_corners[from[i]], _corners[to[i]], f)!,
    );
  }

  /// Rotación por esquinas (l38): cada ciclo los puntos avanzan una esquina.
  List<Offset> _cornersStops(double t) {
    final k = (t * 4).floor() % 4;
    final f = (t * 4) % 1.0;
    // Suavizado para deslizar en vez de saltar.
    final s = f * f * (3 - 2 * f);
    return List<Offset>.generate(
      4,
      (i) => Offset.lerp(_corners[(i + k) % 4], _corners[(i + k + 1) % 4], s)!,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stops = shuffle ? _shuffleStops(progress) : _cornersStops(progress);
    final paint = Paint()..color = color;
    // 40% del lado como en CSS (background-size 40%): radio = 20%.
    final r = size.width * 0.2;
    for (final u in stops) {
      canvas.drawCircle(Offset(u.dx * size.width, u.dy * size.height), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FourDotsPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.shuffle != shuffle ||
        oldDelegate.color != color;
  }
}
