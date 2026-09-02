import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_i18n.dart';
import '../../services/image_cache_service.dart';
import '../../theme/exodo_theme.dart';
import 'image_viewer_screen.dart';

/// Efecto Shimmer reutilizable con barrido diagonal suave.
class ExodoShimmer extends StatefulWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final Color? baseColor;
  final Color? highlightColor;

  const ExodoShimmer({
    super.key,
    required this.child,
    this.borderRadius,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<ExodoShimmer> createState() => _ExodoShimmerState();
}

class _ExodoShimmerState extends State<ExodoShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final base = widget.baseColor ??
        (isLight ? const Color(0xFFE9E5DC) : const Color(0xFF2A2A2A));
    final highlight = widget.highlightColor ??
        (isLight ? const Color(0xFFFFFFFF) : const Color(0xFF4A4136));

    return Container(
      decoration: BoxDecoration(
        color: base,
        borderRadius: widget.borderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final v = _controller.value;
          return ShaderMask(
            blendMode: BlendMode.srcOver,
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment(-1.5 + 3.0 * v, -1.5),
                end: Alignment(-0.5 + 3.0 * v, 1.5),
                colors: [
                  highlight.withValues(alpha: 0.0),
                  highlight.withValues(alpha: 0.16),
                  highlight.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.5, 1.0],
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Placeholder premium mientras Éxodo genera la foto (T2I DashScope).
///
/// Diseño cinemático:
/// - Lienzo cuadrado 1:1 (300x300) que coincide con la proporción de la foto.
/// - Aura de respiración de gradiente ámbar/grafito.
/// - Órbita dual rotativa con apertura fotográfica/chispa central pulsante.
/// - Indicador de estado sincronizado con el tema.
class ImageGeneratingPlaceholder extends StatefulWidget {
  final bool isDownloading;
  final double? progress;

  const ImageGeneratingPlaceholder({
    super.key,
    this.isDownloading = false,
    this.progress,
  });

  @override
  State<ImageGeneratingPlaceholder> createState() =>
      _ImageGeneratingPlaceholderState();
}

class _ImageGeneratingPlaceholderState extends State<ImageGeneratingPlaceholder>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  late final Animation<double> _pulseAnim = CurvedAnimation(
    parent: _pulseController,
    curve: Curves.easeInOutSine,
  );

  @override
  void dispose() {
    _pulseController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cardBg = isLight ? const Color(0xFFF6F3EC) : const Color(0xFF181716);
    final borderColor =
        isLight ? const Color(0x18000000) : const Color(0x2AFFFFFF);
    final textPrimary =
        isLight ? const Color(0xFF1E1C1A) : const Color(0xFFF3EFE6);
    final textMuted =
        isLight ? const Color(0xFF7A7365) : const Color(0xFF9A9385);

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseAnim, _spinController]),
          builder: (context, _) {
            final pulseVal = _pulseAnim.value;
            final spinVal = _spinController.value * 2 * math.pi;

            return Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: ExodoColors.amber.withValues(
                      alpha: isLight
                          ? 0.05 + 0.05 * pulseVal
                          : 0.08 + 0.08 * pulseVal,
                    ),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.85 + 0.25 * pulseVal,
                  colors: [
                    ExodoColors.amber.withValues(
                      alpha: isLight ? 0.08 + 0.06 * pulseVal : 0.12 + 0.08 * pulseVal,
                    ),
                    cardBg,
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Sutil rejilla o halo de fondo
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _AuraCanvasPainter(
                        pulse: pulseVal,
                        isLight: isLight,
                      ),
                    ),
                  ),

                  // Centro: Órbita dual y gema/apertura pulsante
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Anillo orbital giratorio con gradiente
                            Transform.rotate(
                              angle: spinVal,
                              child: CustomPaint(
                                size: const Size(76, 76),
                                painter: _OrbitalRingPainter(
                                  pulse: pulseVal,
                                  isLight: isLight,
                                ),
                              ),
                            ),
                            // Núcleo pulsante
                            Transform.scale(
                              scale: 0.94 + 0.12 * pulseVal,
                              child: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isLight
                                      ? Colors.white
                                      : const Color(0xFF242220),
                                  border: Border.all(
                                    color: ExodoColors.amber.withValues(
                                      alpha: 0.45 + 0.35 * pulseVal,
                                    ),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: ExodoColors.amber.withValues(
                                        alpha: 0.25 + 0.25 * pulseVal,
                                      ),
                                      blurRadius: 16,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.auto_awesome,
                                  size: 22,
                                  color: ExodoColors.amber,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Título con punto pulsante
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ExodoColors.amber.withValues(
                                alpha: 0.4 + 0.6 * pulseVal,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: ExodoColors.amber.withValues(
                                    alpha: 0.5 * pulseVal,
                                  ),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppI18n.of(context).t('chat.creating_image'),
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Subtítulo elegante
                      Opacity(
                        opacity: 0.75 + 0.25 * pulseVal,
                        child: Text(
                          widget.isDownloading && widget.progress != null
                              ? '${(widget.progress! * 100).toInt()}%'
                              : AppI18n.of(context).t('chat.image_synthesizing'),
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400,
                            color: textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Revelación cinemática y renderizado con persistencia total en disco.
class ExodoRevealedImage extends StatefulWidget {
  final String imageUrl;
  final String? altText;

  const ExodoRevealedImage({
    super.key,
    required this.imageUrl,
    this.altText,
  });

  @override
  State<ExodoRevealedImage> createState() => _ExodoRevealedImageState();
}

class _ExodoRevealedImageState extends State<ExodoRevealedImage>
    with SingleTickerProviderStateMixin {
  File? _cachedFile;
  bool _isLoading = true;
  double? _downloadProgress;

  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  late final Animation<double> _fadeAnim = CurvedAnimation(
    parent: _revealController,
    curve: Curves.easeOutCubic,
  );

  late final Animation<double> _scaleAnim = Tween<double>(
    begin: 0.96,
    end: 1.0,
  ).animate(CurvedAnimation(
    parent: _revealController,
    curve: Curves.easeOutCubic,
  ));

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant ExodoRevealedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    // 1. Chequeo ultra-rápido síncrono en disco/memoria (0ms)
    final existing = ImageCacheService.getCachedFileFast(widget.imageUrl);
    if (existing != null && existing.existsSync() && existing.lengthSync() > 0) {
      if (mounted) {
        setState(() {
          _cachedFile = existing;
          _isLoading = false;
        });
        _revealController.value = 1.0; // Ya está cargada, sin demora
      }
      return;
    }

    // 2. Descarga y guardado atómico persistente en disco
    setState(() => _isLoading = true);
    final file = await ImageCacheService.getOrDownloadImage(
      widget.imageUrl,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      },
    );

    if (!mounted) return;
    if (file != null && file.existsSync()) {
      setState(() {
        _cachedFile = file;
        _isLoading = false;
      });
      // Disparar animación cinemática de revelado
      _revealController.forward(from: 0.0);
    } else {
      // Fallback a red si hubo problema de filesystem
      setState(() => _isLoading = false);
      _revealController.value = 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return ImageGeneratingPlaceholder(
        isDownloading: true,
        progress: _downloadProgress,
      );
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    final borderColor =
        isLight ? const Color(0x18000000) : const Color(0x2EFFFFFF);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isLight ? 0.07 : 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ImageViewerScreen(
                        imageUrl: widget.imageUrl,
                      ),
                    ),
                  );
                },
                child: _cachedFile != null
                    ? Image.file(
                        _cachedFile!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      )
                    : Image.network(
                        widget.imageUrl,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        errorBuilder: (context, error, stackTrace) => SelectableText(
                          widget.altText ?? widget.imageUrl,
                          style: const TextStyle(
                            fontFamily: 'AnthropicSans',
                            fontSize: 13,
                            color: ExodoColors.amber,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbitalRingPainter extends CustomPainter {
  final double pulse;
  final bool isLight;

  _OrbitalRingPainter({required this.pulse, required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    final paint1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          ExodoColors.amber.withValues(alpha: 0.1),
          ExodoColors.amber.withValues(alpha: 0.85 + 0.15 * pulse),
          ExodoColors.amber.withValues(alpha: 0.1),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 1.35,
      false,
      paint1,
    );

    final paint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = (isLight ? Colors.black12 : Colors.white12);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 1.5,
      math.pi * 0.35,
      false,
      paint2,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitalRingPainter oldDelegate) => true;
}

class _AuraCanvasPainter extends CustomPainter {
  final double pulse;
  final bool isLight;

  _AuraCanvasPainter({required this.pulse, required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = (isLight ? Colors.black : Colors.white)
          .withValues(alpha: 0.02 + 0.015 * pulse)
      ..strokeWidth = 1.0;

    // Líneas sutiles de composición fotográfica (regla de los tercios)
    final wThird = size.width / 3;
    final hThird = size.height / 3;

    canvas.drawLine(Offset(wThird, 0), Offset(wThird, size.height), linePaint);
    canvas.drawLine(
        Offset(wThird * 2, 0), Offset(wThird * 2, size.height), linePaint);
    canvas.drawLine(Offset(0, hThird), Offset(size.width, hThird), linePaint);
    canvas.drawLine(
        Offset(0, hThird * 2), Offset(size.width, hThird * 2), linePaint);
  }

  @override
  bool shouldRepaint(covariant _AuraCanvasPainter oldDelegate) => true;
}
