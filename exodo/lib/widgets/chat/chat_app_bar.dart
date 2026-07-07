import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../theme/exodo_theme.dart';
import '../../l10n/app_i18n.dart';

class ChatAppBar extends StatelessWidget {
  const ChatAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    // Selectores específicos: solo se reconstruye si cambia isDarkMode o isIncognito.
    // Durante el streaming de texto de la IA (50 chunks/seg), ¡NUNCA se repinta!
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);
    final isLight = !isDarkMode && !isIncognito;
    final state = context.read<AppState>();

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
