import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../services/stripe_service.dart';
import '../../theme/exodo_theme.dart';
import '../../l10n/app_i18n.dart';

// Hoja de selección de modelos y velocidad (Diseño Claude / Minimalista)
class ModelSelectorSheet extends StatelessWidget {
  const ModelSelectorSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode && !state.isIncognito;

    final primaryText = isLight ? const Color(0xFF191919) : ExodoColors.textPrimary;
    final secondaryText = isLight ? const Color(0xFF6B6B6F) : ExodoColors.textSecondary;
    final cardBgUnselected = isLight ? const Color(0xFFF6F5F2) : const Color(0xFF222225);
    final cardBgSelected = isLight ? const Color(0xFFFFFDF9) : const Color(0xFF2C2822);
    final borderColorSelected = ExodoColors.amber.withValues(alpha: isLight ? 0.8 : 0.6);
    final borderColorUnselected = isLight ? const Color(0xFFE5E4DF) : const Color(0xFF333338);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pill handle superior
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: isLight
                      ? const Color(0xFFD6D4CD)
                      : const Color(0xFF4A4A4F),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Encabezado
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Modelo e Inteligencia',
                  style: TextStyle(
                    fontFamily: 'AnthropicSans',
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    letterSpacing: -0.3,
                    color: primaryText,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ExodoColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: ExodoColors.amber.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    state.chatMode.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'AnthropicSans',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: ExodoColors.amber,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── SECCIÓN 1: SELECCIÓN DE MODELO ─────────────────────────────
            Row(
              children: exodoModels.map((m) {
                final active = state.selectedModel.id == m.id;
                final isProModel = m.plan == 'hazak';
                final isFree = state.profile?.plan != 'hazak';

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (state.isIncognito) return;
                      if (isProModel && isFree) {
                        Navigator.pop(context);
                        Future.delayed(const Duration(milliseconds: 150), () {
                          if (context.mounted) UpgradeModal.show(context);
                        });
                        return;
                      }
                      HapticFeedback.selectionClick();
                      state.selectModelOption(m);
                    },
                    child: Container(
                      margin: EdgeInsets.only(
                        right: m == exodoModels.first ? 6 : 0,
                        left: m == exodoModels.last ? 6 : 0,
                      ),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: active ? cardBgSelected : cardBgUnselected,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: active ? borderColorSelected : borderColorUnselected,
                          width: active ? 1.5 : 1.0,
                        ),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: ExodoColors.amber.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                m.title,
                                style: TextStyle(
                                  fontFamily: 'AnthropicSans',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: active ? ExodoColors.amber : primaryText,
                                ),
                              ),
                              if (isProModel)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ExodoColors.amber.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: ExodoColors.amber.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: const Text(
                                    'PRO',
                                    style: TextStyle(
                                      fontFamily: 'AnthropicSans',
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: ExodoColors.amber,
                                    ),
                                  ),
                                )
                              else
                                Icon(
                                  active
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 16,
                                  color: active
                                      ? ExodoColors.amber
                                      : (isLight ? Colors.black26 : Colors.white24),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            m.subtitle,
                            style: TextStyle(
                              fontFamily: 'AnthropicSans',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: active ? primaryText : secondaryText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            m.id == 'origo'
                                ? 'Conversación ágil y tareas cotidianas.'
                                : 'Máxima potencia lógica y razonamiento.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'AnthropicSans',
                              fontSize: 11,
                              color: secondaryText,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // ── SECCIÓN 2: VELOCIDAD Y RAZONAMIENTO (TIPO CLAUDE) ───────────
            Text(
              'VELOCIDAD Y RAZONAMIENTO',
              style: TextStyle(
                fontFamily: 'AnthropicSans',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: secondaryText,
              ),
            ),
            const SizedBox(height: 10),

            _ClaudeSpeedSelector(state: state, isLight: isLight),
          ],
        ),
      ),
    );
  }
}

/// Selector de velocidad y pensamiento estilo Claude (Segmented Cards)
class _ClaudeSpeedSelector extends StatelessWidget {
  final AppState state;
  final bool isLight;

  const _ClaudeSpeedSelector({
    required this.state,
    required this.isLight,
  });

  static const List<_SpeedOption> _options = [
    _SpeedOption(
      id: 'flash',
      title: 'Flash',
      badge: 'Rápido',
      icon: Icons.bolt_rounded,
      description: 'Respuesta instantánea (<200ms) sin pausas de razonamiento.',
    ),
    _SpeedOption(
      id: 'auto',
      title: 'Automático',
      badge: 'Equilibrado',
      icon: Icons.tune_rounded,
      description: 'Adapta la velocidad según la complejidad de la consulta.',
    ),
    _SpeedOption(
      id: 'deep',
      title: 'Deep',
      badge: 'Thinking',
      icon: Icons.psychology_rounded,
      description: 'Razonamiento profundo paso a paso para análisis complejos.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final primaryText = isLight ? const Color(0xFF191919) : ExodoColors.textPrimary;
    final secondaryText = isLight ? const Color(0xFF6B6B6F) : ExodoColors.textSecondary;
    final cardBgUnselected = isLight ? const Color(0xFFF6F5F2) : const Color(0xFF222225);
    final cardBgSelected = isLight ? const Color(0xFFFFFDF9) : const Color(0xFF2C2822);
    final borderColorSelected = ExodoColors.amber.withValues(alpha: isLight ? 0.8 : 0.6);
    final borderColorUnselected = isLight ? const Color(0xFFE5E4DF) : const Color(0xFF333338);

    return Column(
      children: _options.map((opt) {
        final isSelected = state.chatMode == opt.id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.selectionClick();
              state.setChatMode(opt.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? cardBgSelected : cardBgUnselected,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? borderColorSelected : borderColorUnselected,
                  width: isSelected ? 1.4 : 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: ExodoColors.amber.withValues(alpha: 0.07),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? ExodoColors.amber.withValues(alpha: 0.16)
                          : (isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.06)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      opt.icon,
                      size: 18,
                      color: isSelected
                          ? ExodoColors.amber
                          : (isLight ? const Color(0xFF4A4A4F) : Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              opt.title,
                              style: TextStyle(
                                fontFamily: 'AnthropicSans',
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: isSelected ? ExodoColors.amber : primaryText,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? ExodoColors.amber.withValues(alpha: 0.15)
                                    : (isLight ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.07)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                opt.badge,
                                style: TextStyle(
                                  fontFamily: 'AnthropicSans',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? ExodoColors.amber
                                      : secondaryText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          opt.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'AnthropicSans',
                            fontSize: 11,
                            color: secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: isSelected
                        ? ExodoColors.amber
                        : (isLight ? Colors.black26 : Colors.white24),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SpeedOption {
  final String id;
  final String title;
  final String badge;
  final IconData icon;
  final String description;

  const _SpeedOption({
    required this.id,
    required this.title,
    required this.badge,
    required this.icon,
    required this.description,
  });
}


class PulsingXpiAura extends StatefulWidget {
  final Widget child;
  const PulsingXpiAura({super.key, required this.child});
  @override
  State<PulsingXpiAura> createState() => _PulsingXpiAuraState();
}

class _PulsingXpiAuraState extends State<PulsingXpiAura>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
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
        final blur = 3.0 + _ctrl.value * 12.0;
        final op = 0.2 + _ctrl.value * 0.5;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: ExodoColors.amber.withValues(alpha: op),
                blurRadius: blur,
                spreadRadius: 1,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}

class UpgradeModal {
  static void show(BuildContext context) {
    HapticFeedback.vibrate();
    bool isAnnual = false;
    bool isLoadingCheckout = false;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bgColor = isLight ? Colors.white : ExodoColors.background;
    final planSelectedBg = isLight
        ? Colors.white
        : const Color(0xFF191919);
    final planUnselectedBg = isLight
        ? ExodoColors.textPrimary
        : const Color(0xFF252525);
    final composerBg = isLight
        ? ExodoColors.textPrimary
        : ExodoColors.composerBg;
    final borderColor = isLight
        ? const Color(0xFFD1D1D6)
        : Colors.transparent;
    final textPrimary = isLight
        ? const Color(0xFF191919)
        : const Color(0xFFFFFFFF);
    final textSecondary = isLight
        ? const Color(0xFF191919)
        : ExodoColors.textPrimary;
    final radioOff = isLight
        ? const Color(0xFF191919)
        : Colors.white24;
    final buttonBg = isLight
        ? const Color(0xFF191919)
        : const Color(0xFFFFFFFF);
    final buttonFg = isLight
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: textSecondary),
                  onPressed: () => Navigator.pop(ctx),
                ),
                Center(
                  child: Column(
                    children: [
                      Text(
                        AppI18n.of(context).t('billing.title'),
                        style: TextStyle(fontFamily: 'Syne', 
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppI18n.of(context).t('billing.header_sub'),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: composerBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'XPi PRO',
                        style: TextStyle(fontFamily: 'Syne', 
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppI18n.of(context).t('billing.subtitle'),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setModalState(() => isAnnual = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: !isAnnual ? planSelectedBg : planUnselectedBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: !isAnnual
                                        ? ExodoColors.amber
                                        : borderColor,
                                    width: !isAnnual ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      !isAnnual
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked,
                                      size: 18,
                                      color: !isAnnual
                                          ? ExodoColors.amber
                                          : radioOff,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '\$4.99',
                                      style: TextStyle(fontFamily: 'AnthropicSans', 
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: textPrimary,
                                      ),
                                    ),
                                    Text(
                                      AppI18n.of(
                                        context,
                                      ).t('billing.billed_monthly'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => isAnnual = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isAnnual ? planSelectedBg : planUnselectedBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isAnnual
                                        ? ExodoColors.amber
                                        : borderColor,
                                    width: isAnnual ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Icon(
                                          isAnnual
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_unchecked,
                                          size: 18,
                                          color: isAnnual
                                              ? ExodoColors.amber
                                              : radioOff,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: ExodoColors.amber
                                                    .withValues(
                                                  alpha: 0.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  6,
                                                ),
                                              ),
                                              child: Text(
                                                AppI18n.of(
                                                  context,
                                                ).t('billing.save_pct'),
                                                style: GoogleFonts.inter(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: ExodoColors.amber,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '\$49.99',
                                      style: TextStyle(fontFamily: 'AnthropicSans', 
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: textPrimary,
                                      ),
                                    ),
                                    Text(
                                      AppI18n.of(
                                        context,
                                      ).t('billing.billed_annually'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonBg,
                            foregroundColor: buttonFg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: isLoadingCheckout
                              ? null
                              : () async {
                                  HapticFeedback.mediumImpact();
                                  setModalState(() => isLoadingCheckout = true);
                                  final success = await StripeService.startCheckoutSession(context, isAnnual: isAnnual);
                                  if (context.mounted && success) {
                                    Navigator.pop(ctx);
                                  } else if (context.mounted) {
                                    setModalState(() => isLoadingCheckout = false);
                                  }
                                },
                          child: isLoadingCheckout
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: buttonFg,
                                  ),
                                )
                              : Text(
                                  AppI18n.of(context).t('billing.get_pro'),
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          AppI18n.of(context).t('billing.no_commitments'),
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: textSecondary.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        AppI18n.of(context).t('billing.pro_features'),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _item(
                        AppI18n.of(context).t('billing.feat1'),
                        textSecondary,
                      ),
                      _item(
                        AppI18n.of(context).t('billing.feat2'),
                        textSecondary,
                      ),
                      _item(
                        AppI18n.of(context).t('billing.feat3'),
                        textSecondary,
                      ),
                      _item(
                        AppI18n.of(context).t('billing.feat4'),
                        textSecondary,
                      ),
                      _item(
                        AppI18n.of(context).t('billing.feat5'),
                        textSecondary,
                      ),
                      _item(
                        AppI18n.of(context).t('billing.feat6'),
                        textSecondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _item(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.check, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 12.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
