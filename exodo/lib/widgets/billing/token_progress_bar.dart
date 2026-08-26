import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_i18n.dart';
import '../../theme/exodo_theme.dart';

/// Widget interactivo TokenProgressBar:
/// Barra de progreso con indicador numérico, animación, porcentaje,
/// desplegable de estadísticas con píldoras de Consumido, Disponible y cuenta regresiva de reinicio.
class TokenProgressBar extends StatefulWidget {
  final int used;
  final int limit;
  final DateTime? resetTime;
  final bool isPro;

  const TokenProgressBar({
    super.key,
    required this.used,
    required this.limit,
    this.resetTime,
    required this.isPro,
  });

  @override
  State<TokenProgressBar> createState() => _TokenProgressBarState();
}

class _TokenProgressBarState extends State<TokenProgressBar> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  Timer? _timer;

  // P3 batería: el timer de 1s SOLO vive mientras el panel está expandido
  // (es lo único que muestra la cuenta regresiva con segundos).
  void _setExpanded(bool expanded) {
    if (_isExpanded == expanded) return;
    setState(() => _isExpanded = expanded);
    if (expanded) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _getCountdown() {
    if (widget.resetTime == null || widget.used == 0) {
      return '24h 00m';
    }
    final diff = widget.resetTime!.difference(DateTime.now());
    if (diff.isNegative) {
      return '00h 00m';
    }
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${h}h ${m}m ${s}s';
  }

  Widget _infoPill(String label, String value, bool isLight, bool isAmber) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9.5,
            color: isLight ? Colors.black54 : ExodoColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'AnthropicSans',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isAmber
                ? ExodoColors.amber
                : (isLight ? const Color(0xFF191919) : Colors.white),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLimit = widget.limit > 0 ? widget.limit : 6000;
    final progress = (widget.used / effectiveLimit).clamp(0.0, 1.0);
    final remaining = (effectiveLimit - widget.used).clamp(0, effectiveLimit);
    final pct = (progress * 100).toStringAsFixed(1);
    final isLight = Theme.of(context).brightness == Brightness.light;

    final bgColor = isLight ? const Color(0xFFF7F7F7) : ExodoColors.tokenBarBg;
    final trackColor = isLight ? Colors.black12 : ExodoColors.modelChipBg;
    final fillColor = isLight ? const Color(0xFF191919) : ExodoColors.textPrimary;
    final textColor = isLight ? const Color(0xFF171615) : ExodoColors.textPrimary;
    final subTextColor = ExodoColors.textSecondary;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _setExpanded(!_isExpanded);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isExpanded
                ? (isLight ? ExodoColors.amber : ExodoColors.amber.withValues(alpha: 0.6))
                : (isLight ? Colors.black12 : const Color(0xFF2C2C2C)),
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '${widget.used}/$effectiveLimit',
                  style: TextStyle(
                    fontFamily: 'AnthropicSans',
                    fontSize: 11.5,
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: trackColor,
                      valueColor: AlwaysStoppedAnimation<Color>(fillColor),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: _isExpanded
                        ? ExodoColors.amber
                        : subTextColor,
                  ),
                ),
              ],
            ),
            if (_isExpanded) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : const Color(0xFF131313),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isLight ? Colors.black.withValues(alpha: 0.06) : const Color(0xFF242424),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _infoPill(
                      AppI18n.of(context).t('tokens.used'),
                      '${widget.used} ($pct%)',
                      isLight,
                      false,
                    ),
                    if (widget.isPro)
                      _infoPill(
                        AppI18n.of(context).t('tokens.available'),
                        '$remaining tk',
                        isLight,
                        false,
                      ),
                    _infoPill(
                      AppI18n.of(context).t('tokens.reset_in'),
                      _getCountdown(),
                      isLight,
                      true,
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
