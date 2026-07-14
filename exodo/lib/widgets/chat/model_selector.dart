import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../theme/exodo_theme.dart';
import '../../l10n/app_i18n.dart';

// Hoja de selección de modelos (Regla 12: Exodo sin tilde)
class ModelSelectorSheet extends StatelessWidget {
  const ModelSelectorSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode && !state.isIncognito;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: isLight
                    ? const Color(0xFFF5F2EB)
                    : const Color(0xFF191919),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          ...exodoModels.map((m) {
            final active = state.selectedModel.id == m.id;
            final isProModel = m.plan == 'hazak';
            final isFree = state.profile?.plan != 'hazak';

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 2,
              ),
              onTap: () {
                if (state.isIncognito) return;
                if (isProModel && isFree) {
                  Navigator.pop(context);
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (context.mounted) UpgradeModal.show(context);
                  });
                } else {
                  state.selectModelOption(m);
                  Navigator.pop(context);
                }
              },
              title: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    m.title,
                    style: TextStyle(fontFamily: 'AnthropicSans', 
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: active
                          ? ExodoColors.amber
                          : (isLight ? const Color(0xFF191919) : ExodoColors.textPrimary),
                    ),
                  ),
                  Text(
                    m.subtitle,
                    style: TextStyle(fontFamily: 'AnthropicSans', 
                      fontSize: 13,
                      color: isLight ? const Color(0xFF191919) : ExodoColors.textSecondary,
                    ),
                  ),
                  if (isProModel)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? ExodoColors.amber.withValues(alpha: 0.18)
                            : (isLight
                                  ? const Color(0xFFE8E8E8)
                                  : const Color(0xFF222222)),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: active
                              ? ExodoColors.amber
                              : (isLight ? Colors.black12 : Colors.white24),
                        ),
                      ),
                      child: Text(
                        'PRO',
                        style: TextStyle(fontFamily: 'AnthropicSans', 
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: active
                              ? ExodoColors.amber
                              : (isLight
                                    ? ExodoColors.surface
                                    : ExodoColors.textPrimary),
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                AppI18n.of(context).t('models.${m.id}_desc'),
                style: TextStyle(fontFamily: 'AnthropicSans', 
                  fontSize: 11.5,
                  color: isLight ? const Color(0xFF191919) : ExodoColors.textSecondary,
                ),
              ),
              trailing: active
                  ? const Icon(Icons.check, size: 18, color: ExodoColors.amber)
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              tileColor: Colors.transparent,
            );
          }),
          const SizedBox(height: 16),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology_rounded,
                  size: 15,
                  color: ExodoColors.amber.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Text(
                  AppI18n.of(context).t('models.thinking_default'),
                  style: TextStyle(fontFamily: 'AnthropicSans', 
                    fontSize: 11,
                    color: isLight ? const Color(0xFF191919) : ExodoColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
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
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            Navigator.pop(context);
                            // Pago no disponible aún — silencioso
                          },
                          child: Text(
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
