import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Cuadro de espera minimalista para generación de foto:
/// - Cuadro cuadrado 1:1 (300x300) que reserva el espacio exacto de la foto.
/// - Completamente vacío, limpio y sin texto.
/// - Fluctuación ultra suave y calmada (3000 ms) sin parpadeos bruscos ni efecto estroboscópico en OLED/dark mode.
class ImageGeneratingPlaceholder extends StatefulWidget {
  const ImageGeneratingPlaceholder({super.key});

  @override
  State<ImageGeneratingPlaceholder> createState() =>
      _ImageGeneratingPlaceholderState();
}

class _ImageGeneratingPlaceholderState extends State<ImageGeneratingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat(reverse: true);

  late final Animation<double> _pulseAnim = CurvedAnimation(
    parent: _pulseController,
    curve: Curves.easeInOutSine,
  );

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, _) {
            final v = _pulseAnim.value;
            // Respiración sutil y aterciopelada: delta de tono mínimo para evitar parpadeos bruscos
            final surfaceColor = isLight
                ? Color.lerp(const Color(0xFFE8E6E0), const Color(0xFFF3F1EC), v)!
                : Color.lerp(const Color(0xFF1E1E1E), const Color(0xFF292929), v)!;

            final borderColor = isLight
                ? Colors.black.withValues(alpha: 0.04 + 0.03 * v)
                : Colors.white.withValues(alpha: 0.05 + 0.03 * v);

            return Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor, width: 1.0),
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
        _revealController.value = 1.0; // Ya está en disco, sin demora
      }
      return;
    }

    // 2. Descarga y guardado atómico persistente en disco
    setState(() => _isLoading = true);
    final file = await ImageCacheService.getOrDownloadImage(widget.imageUrl);

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
      return const ImageGeneratingPlaceholder();
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
