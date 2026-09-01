import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_i18n.dart';
import '../../theme/exodo_theme.dart';

/// Efecto Shimmer reutilizable: un contenedor con barrido de brillo animado.
/// Se usa como base del placeholder de imagen en generación y como estado de
/// carga de las imágenes de red (loadingBuilder).
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

/// Placeholder que se muestra en lugar de la burbuja "thinking" mientras el
/// backend espera la respuesta de DashScope (t2i). Simula el espacio de la
/// futura imagen con un shimmer y un texto centrado.
class ImageGeneratingPlaceholder extends StatelessWidget {
  const ImageGeneratingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor =
        isLight ? const Color(0xFF171615) : ExodoColors.textPrimary;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: ExodoShimmer(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 260,
            height: 230,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isLight ? Colors.black12 : Colors.white12,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: ExodoColors.amber,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppI18n.of(context).t('chat.creating_image'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}