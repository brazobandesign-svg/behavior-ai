import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../theme/exodo_theme.dart';
import '../../l10n/app_i18n.dart';

class ChatAppBar extends StatelessWidget {
  const ChatAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    // Selectores específicos y escucha del estado del chat
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);
    final isGuestUser = context.select<AppState, bool>((s) => s.isGuestUser);
    final isLight = !isDarkMode && !isIncognito;
    final state = context.watch<AppState>();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      child: Row(
        children: [
          // Regla 1: Menú Profile estilo Library (3 líneas escalonadas)
          Builder(
            builder: (ctx) => InkWell(
              onTap: () => Scaffold.of(ctx).openDrawer(),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 2,
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.black87
                            : ExodoColors.textPrimary,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 20,
                      height: 2,
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.black87
                            : ExodoColors.textPrimary,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 12,
                      height: 2,
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.black87
                            : ExodoColors.textPrimary,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Regla 4: Contador de tokens reubicado al header entre menú e iconos de la derecha
          if (!isIncognito && !isGuestUser)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _HeaderTokenBar(
                  used: state.tokensUsed,
                  limit: state.tokensLimit,
                  resetTime: state.tokensResetTime,
                  isPro: state.isPro,
                ),
              ),
            )
          else
            const Spacer(),

          // En modo incógnito quitar iconos New Chat y Dark Mode
          if (!isIncognito) ...[
            // 1. Nuevo Chat
            IconButton(
              icon: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 21,
                color: isLight
                    ? Colors.black87
                    : ExodoColors.textSecondary,
              ),
              tooltip: 'Nuevo chat',
              onPressed: () => state.startNewChat(),
            ),

            // 2. Dark / Light Mode
            IconButton(
              icon: Icon(
                isDarkMode
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                size: 22,
                color: isLight
                    ? Colors.black87
                    : ExodoColors.textSecondary,
              ),
              tooltip: 'Cambiar tema',
              onPressed: () => state.toggleTheme(),
            ),
          ],

          // 3. Incógnito (botón para activarlo o salir)
          IconButton(
            icon: _AnimatedIncognitoHat(
              isIncognito: isIncognito,
              child: Image.asset(
                'assets/images/incognito-svgrepo-com.png',
                width: 22,
                height: 22,
                color: isIncognito
                    ? Colors.white
                    : (isLight
                          ? Colors.black87
                          : ExodoColors.textSecondary),
              ),
            ),
            tooltip: AppI18n.of(context).t('drawer.incognito'),
            onPressed: () {
              state.toggleIncognito();
            },
          ),
        ],
      ),
    );
  }
}

class _AnimatedIncognitoHat extends StatefulWidget {
  final bool isIncognito;
  final Widget child;
  const _AnimatedIncognitoHat({required this.isIncognito, required this.child});
  @override
  State<_AnimatedIncognitoHat> createState() => _AnimatedIncognitoHatState();
}

class _AnimatedIncognitoHatState extends State<_AnimatedIncognitoHat>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _anim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: -8.0,
        ).chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -8.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 60,
      ),
    ]).animate(_ctrl);
    if (widget.isIncognito) {
      _ctrl.forward();
    }
  }

  @override
  void didUpdateWidget(_AnimatedIncognitoHat old) {
    super.didUpdateWidget(old);
    if (widget.isIncognito && !old.isIncognito) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, _anim.value), child: child),
      child: widget.child,
    );
  }
}

class _HeaderTokenBar extends StatefulWidget {
  final int used;
  final int limit;
  final DateTime? resetTime;
  final bool isPro;

  const _HeaderTokenBar({
    required this.used,
    required this.limit,
    this.resetTime,
    required this.isPro,
  });

  @override
  State<_HeaderTokenBar> createState() => _HeaderTokenBarState();
}

class _HeaderTokenBarState extends State<_HeaderTokenBar> {
  final OverlayPortalController _portalController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _portalController.isShowing) setState(() {});
    });
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
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 8,
            color: isLight ? Colors.black54 : ExodoColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(fontFamily: 'AnthropicSans', 
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isAmber
                ? ExodoColors.amber
                : (isLight ? Colors.black87 : Colors.white),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (widget.used / widget.limit).clamp(0.0, 1.0);
    final remaining = (widget.limit - widget.used).clamp(0, widget.limit);
    final pct = (progress * 100).toStringAsFixed(1);
    final isLight = Theme.of(context).brightness == Brightness.light;

    final bgColor = isLight ? const Color(0xFFE8E8E8) : ExodoColors.tokenBarBg;
    final trackColor = isLight ? const Color(0xFFDDDDDD) : const Color(0xFF131313);
    final fillColor = isLight ? const Color(0xFF171615) : ExodoColors.textPrimary;
    final textColor = isLight ? const Color(0xFF171615) : ExodoColors.textPrimary;
    final subTextColor = isLight ? const Color(0xFF7B7872) : ExodoColors.textSecondary;

    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _portalController,
        overlayChildBuilder: (BuildContext ctx) {
          final barWidth = _layerLink.leaderSize?.width ?? 190.0;
          return TapRegion(
            groupId: _portalController,
            onTapOutside: (event) {
              if (_portalController.isShowing) {
                _portalController.hide();
                setState(() {});
              }
            },
            child: CompositedTransformFollower(
              link: _layerLink,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 4),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: barWidth,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ExodoColors.amber.withValues(alpha: 0.4),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _infoPill(
                            'Consumido',
                            '${widget.used} ($pct%)',
                            isLight,
                            false,
                          ),
                          if (widget.isPro)
                            _infoPill(
                              'Disponible',
                              '$remaining tk',
                              isLight,
                              false,
                            ),
                          _infoPill(
                            'Reinicio en',
                            _getCountdown(),
                            isLight,
                            true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: TapRegion(
          groupId: _portalController,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _portalController.toggle();
              });
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    '${widget.used}/${widget.limit}',
                    style: TextStyle(fontFamily: 'AnthropicSans', 
                      fontSize: 9.5,
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: trackColor,
                        valueColor: AlwaysStoppedAnimation<Color>(fillColor),
                        minHeight: 4.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _portalController.isShowing ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 15,
                      color: _portalController.isShowing
                          ? ExodoColors.amber
                          : subTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
