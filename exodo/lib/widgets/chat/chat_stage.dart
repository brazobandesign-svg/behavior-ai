import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/app_state.dart';
import '../../theme/exodo_theme.dart';
import '../../l10n/app_i18n.dart';

// Regla 2 & 7: Fondo ambiental sólido (sin animación innecesaria) con watermark según modo.
// Optimizado con context.select para no reconstruirse durante streaming de chat.
class AnimatedAmbientBackground extends StatelessWidget {
  final Animation<double>? animation;
  final Widget child;
  const AnimatedAmbientBackground({
    this.animation,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Solo se reconstruye si cambia isDarkMode o isIncognito
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);

    final isDarkBg = isDarkMode || isIncognito;
    final bgColor = isDarkBg
        ? ExodoColors.chatBg
        : const Color(0xFFFBF9F5);

    // La watermark ahora vive dentro de ChatStage para garantizar
    // que saludo y PNG nunca choquen.
    return Container(color: bgColor, child: child);
  }
}

class ChatStage extends StatelessWidget {
  final Animation<double>? pulseAnim;
  final String? fullName;
  const ChatStage({
    this.pulseAnim,
    this.fullName,
    super.key,
  });

  String _getGreeting(BuildContext context, double? temp) {
    final i18n = AppI18n.of(context);

    if (temp != null) {
      if (temp <= 21.0) {
        return i18n.t('greeting.cold');
      } else if (temp >= 31.0) {
        return i18n.t('greeting.hot');
      }
    }

    final hour = DateTime.now().hour;
    if (hour >= 0 && hour < 6) return i18n.t('greeting.late');
    if (hour < 12) return i18n.t('greeting.morning');
    if (hour < 18) return i18n.t('greeting.afternoon');
    return i18n.t('greeting.evening');
  }

  @override
  Widget build(BuildContext context) {
    // Selectores específicos: solo reconstruye si cambian estas 3 propiedades de estado.
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final temp = context.select<AppState, double?>((s) => s.currentTempC);

    final isLight =
        Theme.of(context).brightness == Brightness.light && !isIncognito;

    final isDarkBg = isDarkMode || isIncognito;
    final watermarkAsset = isDarkBg
        ? 'assets/images/watermark2.png'
        : 'assets/images/watermark1.png';

    // ============================================================
    // LAYOUT CENTRADO: saludo + watermark como bloque único vertical.
    // Ambos se centran juntos en la pantalla. La watermark va justo
    // debajo del saludo (separación fija de 16px).
    // ============================================================

    final stageWidth = MediaQuery.of(context).size.width;
    final watermarkWidth = stageWidth * 0.40;
    final watermarkHeight = watermarkWidth / 7.0208;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Saludo (original, máximo 2 líneas)
            Text(
              isIncognito
                  ? AppI18n.of(context).t('chat.incognito_title')
                  : _getGreeting(context, temp),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'AnthropicSerif',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isLight ? const Color(0xFF171615) : Colors.white,
                height: 1.15,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),
            // Watermark: segunda línea, justo debajo del saludo
            IgnorePointer(
              child: SizedBox(
                width: watermarkWidth,
                height: watermarkHeight,
                child: Image.asset(watermarkAsset, fit: BoxFit.fill),
              ),
            ),
            if (isIncognito) ...[
              const SizedBox(height: 18),
              Text(
                AppI18n.of(context).t('chat.incognito_desc'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13.5, color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
