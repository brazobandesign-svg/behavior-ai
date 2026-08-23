import 'dart:math';
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
        : ExodoColors.textPrimary;

    // La watermark ahora vive dentro de ChatStage para garantizar
    // que saludo y PNG nunca choquen.
    return Container(color: bgColor, child: child);
  }
}

class ChatStage extends StatefulWidget {
  final Animation<double>? pulseAnim;
  final String? fullName;
  const ChatStage({
    this.pulseAnim,
    this.fullName,
    super.key,
  });

  @override
  State<ChatStage> createState() => _ChatStageState();
}

class _ChatStageState extends State<ChatStage> {
  String _getGreeting(BuildContext context, double? temp) {
    final i18n = AppI18n.of(context);
    final userEmail = context.select<AppState, String>((s) => s.userEmail);
    final profileName = widget.fullName?.trim().isNotEmpty == true
        ? widget.fullName!.trim()
        : (userEmail.isNotEmpty
            ? userEmail.split('@').first.replaceFirstMapped(
                RegExp(r'^[a-z]'), (m) => m[0]!.toUpperCase())
            : 'User');

    final hour = DateTime.now().hour;
    final timeGreeting = (hour >= 0 && hour < 6)
        ? i18n.t('greeting.late')
        : (hour < 12)
            ? i18n.t('greeting.morning')
            : (hour < 18)
                ? i18n.t('greeting.afternoon')
                : i18n.t('greeting.evening');

    final greetings = <String>[
      '$timeGreeting, $profileName',
      i18n.t('greeting.flirt'),
      '${i18n.t('greeting.hot')}, $profileName',
      i18n.t('greeting.flirt'),
      '${i18n.t('greeting.hot')}, $profileName',
    ];

    if (temp != null && temp >= 28.0) {
      greetings.add('${i18n.t('greeting.hot')}, $profileName');
    }

    return greetings[Random().nextInt(greetings.length)];
  }

  @override
  Widget build(BuildContext context) {
    // Selectores específicos: solo reconstruye si cambian estas 3 propiedades de estado.
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final isOnline = context.select<AppState, bool>((s) => s.isOnline);
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

    // Modo Incógnito: Solo disclaimer centrado, sin saludo ni watermark de Éxodo
    if (isIncognito) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                AppI18n.of(context).t('chat.incognito_desc'),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'AnthropicSans',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: ExodoColors.textSecondary,
                  height: 1.4,
                  letterSpacing: -0.1,
                ),
              ),
              if (!isOnline) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 16, color: ExodoColors.amber),
                      const SizedBox(width: 8),
                      Text(
                        AppI18n.of(context).t('network.offline_title'),
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: ExodoColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

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
              _getGreeting(context, temp),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'AnthropicSerif',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
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
            if (!isOnline) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 16, color: ExodoColors.amber),
                    const SizedBox(width: 8),
                    Text(
                      AppI18n.of(context).t('network.offline_title'),
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isLight ? const Color(0xFF171615) : ExodoColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
