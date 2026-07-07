import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/supabase_service.dart';
import '../services/widget_service.dart';
import '../widgets/drawer_menu.dart';
import '../widgets/scroll_to_bottom_button.dart';
import '../widgets/chat/chat_app_bar.dart';
import '../widgets/chat/chat_stage.dart';
import '../widgets/chat/chat_composer.dart';
import '../theme/exodo_theme.dart';
import '../l10n/app_i18n.dart';

// [GLM-P1-2] Antes leía el locale del SISTEMA operativo (PlatformDispatcher +
// Localizations). Eso causaba que, tras cambiar el idioma en el drawer, los
// textos hardcoded siguieran en el idioma del dispositivo.
// Ahora consulta el locale seleccionado en la app vía AppI18n (que vive en
// MaterialApp.locale y persiste en SharedPreferences clave 'exodo_locale').
bool _isDeviceEnglish(BuildContext context) {
  return AppI18n.of(context).localeCode == 'en';
}

String _formatTime(BuildContext context, DateTime dt) {
  final isEn = _isDeviceEnglish(context);
  if (isEn) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour < 12 ? 'AM' : 'PM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $amPm';
  }
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late AnimationController _thinkingAnimCtrl;
  late AnimationController _ambientBgCtrl;
  late AnimationController _pulseCtrl;
  int _lastMessageCount = 0;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    _thinkingAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _ambientBgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
    // Regla 5 & 9: Pulso continuo para cambio de tamaño de puntos aleatorio
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    // Trigger reload
    WidgetService.instance.getInitialPrompt().then((prompt) {
      if (prompt != null && prompt.trim().isNotEmpty && mounted) {
        context.read<AppState>().sendUserMessage(prompt.trim());
      }
    });
    WidgetService.instance.setPromptListener((prompt) {
      if (mounted && prompt.trim().isNotEmpty) {
        context.read<AppState>().sendUserMessage(prompt.trim());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final appState = context.read<AppState>();
    if (state == AppLifecycleState.paused) {
      // [Sprint 0] App minimizada: pausar animaciones para ahorrar batería.
      _thinkingAnimCtrl.stop();
      _ambientBgCtrl.stop();
      _pulseCtrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      // [Sprint 0] App vuelve a primer plano: reanudar animaciones.
      if (appState.isGenerating) {
        _thinkingAnimCtrl.repeat(reverse: true);
      }
      _pulseCtrl.repeat(reverse: true);
      // _ambientBgCtrl no se reanuda (no se usa, bug #9 auditoría).
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _thinkingAnimCtrl.dispose();
    _ambientBgCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showModelSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark
          ? ExodoColors.modelChipBg
          : Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _ModelSelectorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode && !state.isIncognito;
    if (state.currentMessages.length > _lastMessageCount) {
      _lastMessageCount = state.currentMessages.length;
      _scrollToBottom();
    } else {
      _lastMessageCount = state.currentMessages.length;
    }

    return Scaffold(
      drawer: const DrawerMenu(),
      onDrawerChanged: (isOpened) {
        if (isOpened && state.isIncognito) {
          state.exitIncognitoAndClear();
        }
      },
      body: AnimatedAmbientBackground(
        animation: _ambientBgCtrl,
        child: SafeArea(
          child: Column(
            children: [
              // Barra superior minimalista y limpia modularizada
              const ChatAppBar(),

              // Regla 4: Conteo de tokens (desaparece en modo incógnito y modo Guest)
              if (!state.isIncognito && !state.isGuestUser)
                _TokenProgressBar(
                  used: state.tokensUsed,
                  limit: state.tokensLimit,
                  resetTime: state.tokensResetTime,
                  isPro: state.isPro,
                ),

              // [Punto 43] Banner de offline: aparece cuando no hay internet.
              if (!state.isOnline) _NetworkOfflineBanner(isLight: isLight),

              // Stage principal o lista de mensajes (SIEMPRE VISIBLE y fluye tras el composer)
              Expanded(
                child: Stack(
                  children: [
                    if (state.currentMessages.isEmpty)
                      Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 120),
                          physics: const ClampingScrollPhysics(),
                          child: ChatStage(
                            pulseAnim: _pulseCtrl,
                            fullName: state.profile?.fullName,
                          ),
                        ),
                      )
                    else
                      // [Punto 36 aviso] Filtro defensivo: aunque currentMessages
                      // tenga contenido, si NO hay conversación activa seleccionada
                      // Y NO hay un mensaje del usuario en la lista, mostramos el
                      // stage vacío en lugar de mensajes residuales. Esto elimina
                      // el flash de "You stopped the response" o cualquier
                      // mensaje huérfano al iniciar sesión / cambiar de cuenta.
                      Builder(
                        builder: (context) {
                          final hasUserMsg = state.currentMessages.any(
                            (m) => m.role == 'user',
                          );
                          final hasActiveConv =
                              state.activeConversation != null;
                          if (!hasUserMsg &&
                              !hasActiveConv &&
                              !state.isIncognito) {
                            return Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.only(bottom: 120),
                                physics: const ClampingScrollPhysics(),
                                child: ChatStage(
                                  pulseAnim: _pulseCtrl,
                                  fullName: state.profile?.fullName,
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              top: 8,
                              bottom: 160,
                            ),
                            itemCount: state.currentMessages.length,
                            itemBuilder: (context, index) {
                              final msg = state.currentMessages[index];
                              if (msg.isThinking) {
                                return _ThinkingBubble(pulseAnim: _pulseCtrl);
                              }
                              return _MessageBubble(message: msg);
                            },
                          );
                        },
                      ),
                    // Degradado inferior (borrado suave para que el texto fluya sin corte brusco)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: 125,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.0, 0.45, 1.0],
                              colors: [
                                (isLight
                                        ? const Color(0xFFFBF9F5)
                                        : const Color(0xFF20201F))
                                    .withValues(alpha: 0.0),
                                (isLight
                                        ? const Color(0xFFFBF9F5)
                                        : const Color(0xFF20201F))
                                    .withValues(alpha: 0.85),
                                (isLight
                                    ? const Color(0xFFFBF9F5)
                                    : const Color(0xFF20201F)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Botón flotante "scroll to bottom" (esquina inferior derecha).
                    Positioned(
                      right: 16,
                      bottom: 240,
                      child: _ScrollToBottomHost(
                        controller: _scrollCtrl,
                        messagesCount: state.currentMessages.length,
                      ),
                    ),
                    // Barra inferior entrelazada del Tab 1 (SIEMPRE en su sitio exacto flotando)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ChatComposer(
                        controller: _inputCtrl,
                        onSend: (attachments) {
                          final text = _inputCtrl.text;
                          if (text.trim().isEmpty) return;
                          FocusScope.of(context).unfocus();
                          if (!state.isGuestUser &&
                              (state.tokensUsed >= state.tokensLimit ||
                                  state.tokensUsed + (text.length ~/ 3) + 15 >
                                      state.tokensLimit)) {
                            HapticFeedback.vibrate();
                            if (!state.isPro) {
                              _UpgradeModal.show(context);
                            }
                            state.sendUserMessage(text);
                            return;
                          }
                          _inputCtrl.clear();
                          state.sendUserMessage(text, attachments: attachments);
                        },
                        onModelTap: _showModelSheet,
                        onUpgradeTap: () => _UpgradeModal.show(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// [Punto 43] Banner de offline: aparece arriba del chat cuando no hay internet.
class _NetworkOfflineBanner extends StatelessWidget {
  final bool isLight;
  const _NetworkOfflineBanner({required this.isLight});

  @override
  Widget build(BuildContext context) {
    final bg = isLight ? const Color(0xFFE8D5C4) : const Color(0xFF3D2E1C);
    final textColor = isLight
        ? const Color(0xFF5D3A1A)
        : const Color(0xFFE8CBA4);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.signal_wifi_off_rounded, size: 18, color: textColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppI18n.of(context).t('network.offline_body'),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Regla 4 & 10: Barra de tokens interactiva suprema con contador en tiempo real y acomodo simétrico Pro
class _TokenProgressBar extends StatefulWidget {
  final int used;
  final int limit;
  final DateTime? resetTime;
  final bool isPro;

  const _TokenProgressBar({
    required this.used,
    required this.limit,
    this.resetTime,
    required this.isPro,
  });

  @override
  State<_TokenProgressBar> createState() => _TokenProgressBarState();
}

class _TokenProgressBarState extends State<_TokenProgressBar> {
  bool _isExpanded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isExpanded && mounted) {
        setState(() {}); // Actualiza cuenta regresiva segundo a segundo
      }
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

  @override
  Widget build(BuildContext context) {
    final progress = (widget.used / widget.limit).clamp(0.0, 1.0);
    final remaining = (widget.limit - widget.used).clamp(0, widget.limit);
    final pct = (progress * 100).toStringAsFixed(1);
    final isLight = Theme.of(context).brightness == Brightness.light;

    final bgColor = isLight ? const Color(0xFFE5DECF) : ExodoColors.tokenBarBg;
    final trackColor = isLight
        ? const Color(0xFFD4CCBC)
        : const Color(0xFF131313);
    final fillColor = isLight
        ? const Color(0xFF171615)
        : ExodoColors.textPrimary;
    final textColor = isLight
        ? const Color(0xFF171615)
        : ExodoColors.textPrimary;
    final subTextColor = isLight
        ? const Color(0xFF7B7872)
        : ExodoColors.textSecondary;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _isExpanded = !_isExpanded);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pista Principal superior (Siempre visible)
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: trackColor,
                      valueColor: AlwaysStoppedAnimation<Color>(fillColor),
                      minHeight: 4.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${widget.used} / ${widget.limit} tokens',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: _isExpanded ? ExodoColors.amber : subTextColor,
                  ),
                ),
              ],
            ),

            // Desglose secundario emergente
            if (_isExpanded) ...[
              const SizedBox(height: 10),
              Divider(color: trackColor, height: 1),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _statItem(
                    AppI18n.of(context).t('tokens.used'),
                    '${widget.used} ($pct%)',
                    textColor,
                  ),

                  // En PRO acomodamos simétricamente DISPONIBLE en el centro
                  if (widget.isPro)
                    _statItem(
                      AppI18n.of(context).t('tokens.available'),
                      '$remaining',
                      textColor,
                    ),

                  _statItem(
                    AppI18n.of(context).t('tokens.reset_in'),
                    _getCountdown(),
                    ExodoColors.amber,
                  ),

                  // En FREE colocamos MÁS CAPACIDAD a la derecha
                  if (!widget.isPro)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.vibrate();
                        _UpgradeModal.show(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: ExodoColors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: ExodoColors.amber.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.bolt_rounded,
                              size: 12,
                              color: ExodoColors.amber,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              AppI18n.of(context).t('tokens.more'),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                color: ExodoColors.amber,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 8,
            color: ExodoColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// Regla 9: Burbuja de "razonando" mientras la IA piensa.
// FIX v1.2.3: Se quita el Container con padding/decoration porque se
// renderizaba como una caja visible. Ahora es un Row directo sin
// envoltorio decorado, alineado a la izquierda como texto plano.
// [Punto 30 aviso]: junto al logo flecha, texto localizado vía
// `chat.thinking_label` (palabra suelta, sin puntos suspensivos).
// Opacidad fluctuante 25% ↔ 50% sincronizada con el pulseAnim del logo.
class _ThinkingBubble extends StatelessWidget {
  final Animation<double> pulseAnim;
  const _ThinkingBubble({required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode && !state.isIncognito;
    final logoColor = isLight ? ExodoColors.background : ExodoColors.amber;
    // Localización reactiva: cambia de idioma sin necesidad de reiniciar.
    final thinkingLabel = AppI18n.of(context).t('chat.thinking_label');
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: AnimatedBuilder(
          animation: pulseAnim,
          builder: (context, _) {
            final v = pulseAnim.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo flecha: opacidad 40% ↔ 100% (igual que antes).
                Opacity(
                  opacity: 0.4 + (v * 0.6).clamp(0.0, 0.6),
                  child: Image.asset(
                    'assets/images/exodo_arrow_logo.png',
                    width: 28,
                    height: 28,
                    color: logoColor,
                  ),
                ),
                const SizedBox(width: 8),
                // Texto localizado con fluctuación de opacidad 25% ↔ 50%
                // usando la misma curva del pulseAnim (2200ms, repeat reverse).
                Opacity(
                  opacity: 0.25 + (v * 0.25), // 0.25 (v=0) → 0.50 (v=1)
                  child: Text(
                    thinkingLabel,
                    style: TextStyle(
                      color: logoColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Inter',
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Regla 13: Estilo de burbujas tipo Claude (Usuario en rectángulo opuesto SIN colita, IA al descubierto)
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isLight = Theme.of(context).brightness == Brightness.light;

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82,
              ),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isLight
                    ? const Color(0xFFE5DECF)
                    : const Color(0xFF131313),
                borderRadius: BorderRadius.circular(20),
                border: isLight
                    ? Border.all(color: const Color(0xFFD4CEBF), width: 1.0)
                    : null,
              ),
              child: MarkdownBody(
                data: message.content,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                    .copyWith(
                      p: GoogleFonts.inter(
                        fontSize: 15,
                        color: isLight ? const Color(0xFF171615) : Colors.white,
                      ),
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 3),
              child: Text(
                _formatTime(context, message.createdAt),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: isLight ? Colors.black38 : Colors.white38,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  assetPath: 'assets/images/copy-2-svgrepo-com.png',
                  tooltip: AppI18n.of(context).t('act.copy'),
                  color: isLight ? Colors.black38 : Colors.white38,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Clipboard.setData(ClipboardData(text: message.content));
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Respuesta de la IA: AL DESCUBIERTO (Sin fondo, sin borde, puro texto como Claude)
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data: message.content,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  p: GoogleFonts.inter(
                    fontSize: 15.5,
                    color: isLight
                        ? const Color(0xFF171615)
                        : ExodoColors.textPrimary,
                    height: 1.45,
                  ),
                  code: GoogleFonts.jetBrainsMono(
                    backgroundColor: isLight
                        ? const Color(0xFFEFECE4)
                        : ExodoColors.surface,
                    color: isLight
                        ? const Color(0xFFB85A35)
                        : ExodoColors.amber,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: isLight
                        ? const Color(0xFFF2ECE1)
                        : ExodoColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ExodoColors.border),
                  ),
                ),
          ),
          if (message.intentDetected != null) ...[
            const SizedBox(height: 8),
            Text(
              '${AppI18n.of(context).t('chat.intent')}: ${message.intentDetected}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: ExodoColors.amber.withValues(alpha: 0.8),
              ),
            ),
          ],
          if (message.sources.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SourcesSheet(sources: message.sources),
          ],
          const SizedBox(height: 10),
          _MessageActionBar(message: message),
          const SizedBox(height: 14),
          Row(
            children: [
              Image.asset(
                'assets/images/Logo_behavior.png',
                height: 26,
                fit: BoxFit.contain,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Opacity(
            opacity: 0.5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    AppI18n.of(context).t('chat.disclaimer'),
                    textAlign: TextAlign.end,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      height: 1.35,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloque compacto estilo cápsula con el texto "Sources" e íconos superpuestos.
class _SourcesSheet extends StatelessWidget {
  final List<Source> sources;
  const _SourcesSheet({required this.sources});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final label = AppI18n.of(context).t('sources.title');

    final circleColors = [
      const Color(0xFF635BFF),
      const Color(0xFF131313),
      const Color(0xFF2E90FA),
      const Color(0xFFC9933A),
    ];

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        showModalBottomSheet(
          context: context,
          backgroundColor: isLight ? Colors.white : const Color(0xFF131313),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppI18n.of(context).t('sources.consulted'),
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sources.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 16, color: Colors.white12),
                      itemBuilder: (ctx, idx) {
                        final s = sources[idx];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor:
                                circleColors[idx % circleColors.length],
                            child: Text(
                              _sourceInitials(s),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          title: Text(
                            s.title.isNotEmpty ? s.title : s.url,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.black87 : Colors.white,
                            ),
                          ),
                          subtitle: s.url.isNotEmpty
                              ? Text(
                                  s.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: ExodoColors.amber,
                                  ),
                                )
                              : null,
                          trailing: s.url.isNotEmpty
                              ? Icon(
                                  Icons.open_in_new_rounded,
                                  size: 18,
                                  color: ExodoColors.amber,
                                )
                              : null,
                          onTap: s.url.isNotEmpty
                              ? () async {
                                  HapticFeedback.lightImpact();
                                  final uri = Uri.tryParse(s.url);
                                  if (uri != null && await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } else {
                                    Clipboard.setData(
                                      ClipboardData(text: s.url),
                                    );
                                  }
                                }
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isLight ? const Color(0xFFEAE7DF) : const Color(0xFF222224),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isLight ? Colors.black12 : const Color(0xFF333336),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isLight
                    ? const Color(0xFF4A4A4A)
                    : const Color(0xFFA0A0A5),
              ),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (ctx) {
                final displaySources = sources.take(4).toList();
                return SizedBox(
                  height: 20,
                  width: (displaySources.length * 12.0) + 8.0,
                  child: Stack(
                    children: [
                      for (int i = 0; i < displaySources.length; i++)
                        Positioned(
                          left: i * 12.0,
                          child: Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: circleColors[i % circleColors.length],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isLight
                                    ? const Color(0xFFEAE7DF)
                                    : const Color(0xFF222224),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              _sourceInitials(displaySources[i]),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _sourceInitials(Source s) {
  if (s.favicon != null && s.favicon!.isNotEmpty) return s.favicon!;
  final t = s.title.trim();
  if (t.isEmpty) return '?';
  final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2) {
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
  return t.length >= 2
      ? t.substring(0, 2).toUpperCase()
      : t.substring(0, 1).toUpperCase();
}

/// Barra de acciones al pie de cada respuesta del asistente:
/// Copy · Share · Like · Dislike.
class _MessageActionBar extends StatelessWidget {
  final ChatMessage message;
  const _MessageActionBar({required this.message});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final subText = isLight ? Colors.black54 : Colors.white60;

    void copy() {
      HapticFeedback.lightImpact();
      Clipboard.setData(ClipboardData(text: message.content));
    }

    void share() {
      HapticFeedback.lightImpact();
      final playStoreUrl =
          'https://play.google.com/store/apps/details?id=com.behavior.exodo';
      final shareText =
          '${message.content}\n\n${AppI18n.of(context).t('feedback.share_msg')}\n$playStoreUrl';
      Share.share(shareText, subject: 'Éxodo AI');
    }

    void showFeedbackModal(bool isLike) {
      final ctrl = TextEditingController();
      final title = isLike
          ? AppI18n.of(context).t('feedback.title_pos')
          : AppI18n.of(context).t('feedback.title_neg');
      final hint = AppI18n.of(context).t('feedback.hint');

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isLight
              ? const Color(0xFFF5F2EB)
              : ExodoColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                isLike
                    ? Icons.thumb_up_alt_rounded
                    : Icons.thumb_down_alt_rounded,
                color: ExodoColors.amber,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isLight
                        ? const Color(0xFF171615)
                        : ExodoColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: TextField(
            controller: ctrl,
            maxLines: 4,
            minLines: 2,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isLight
                  ? const Color(0xFF171615)
                  : ExodoColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                color: ExodoColors.textSecondary,
                fontSize: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: ExodoColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: ExodoColors.amber),
              ),
              filled: true,
              fillColor: isLight ? Colors.white : const Color(0xFF131313),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                AppI18n.of(context).t('ctx.cancel'),
                style: GoogleFonts.inter(color: ExodoColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () async {
                final feedbackText = ctrl.text.trim();
                Navigator.pop(ctx);
                // [Punto 37 aviso] Feedback directo a Supabase (sin mailto).
                final appCtx =
                    context; // snapshot antes de que el dialog cierre
                final convId = context.read<AppState>().activeConversation?.id;
                final ok = await SupabaseService.submitFeedback(
                  isLike: isLike,
                  comment: feedbackText,
                  messageExcerpt: message.content,
                  conversationId: convId,
                );
                // Feedback enviado silenciosamente
              },
              child: Text(
                AppI18n.of(context).t('action.send'),
                style: GoogleFonts.inter(
                  color: ExodoColors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    void like() {
      HapticFeedback.mediumImpact();
      showFeedbackModal(true);
    }

    void dislike() {
      HapticFeedback.mediumImpact();
      showFeedbackModal(false);
    }

    return Wrap(
      spacing: 18,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ActionButton(
          assetPath: 'assets/images/copy-2-svgrepo-com.png',
          tooltip: AppI18n.of(context).t('act.copy'),
          color: subText,
          onTap: copy,
        ),
        _ActionButton(
          assetPath: 'assets/images/like-1-svgrepo-com.png',
          tooltip: AppI18n.of(context).t('act.like'),
          color: subText,
          onTap: like,
        ),
        _ActionButton(
          assetPath: 'assets/images/like-1-svgrepo-com.png',
          flipVertically: true,
          tooltip: AppI18n.of(context).t('act.dislike'),
          color: subText,
          onTap: dislike,
        ),
        _ActionButton(
          assetPath: 'assets/images/share-svgrepo-com.png',
          tooltip: AppI18n.of(context).t('act.share'),
          color: subText,
          onTap: share,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData? icon;
  final String? assetPath;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  final bool flipVertically;
  const _ActionButton({
    this.icon,
    this.assetPath,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.flipVertically = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget childWidget;
    if (assetPath != null) {
      childWidget = Image.asset(
        assetPath!,
        width: 18,
        height: 18,
        color: color,
      );
    } else {
      childWidget = Icon(icon ?? Icons.circle, size: 18, color: color);
    }
    if (flipVertically) {
      childWidget = Transform.flip(flipY: true, child: childWidget);
    }
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(padding: const EdgeInsets.all(4), child: childWidget),
      ),
    );
  }
}

// Hoja de selección de modelos (Regla 12: Exodo sin tilde)
class _ModelSelectorSheet extends StatelessWidget {
  const _ModelSelectorSheet();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode;

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
                color: isLight ? Colors.black26 : ExodoColors.border,
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
                if (isProModel && isFree) {
                  Navigator.pop(context);
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (context.mounted) _UpgradeModal.show(context);
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
                    style: GoogleFonts.jetBrainsMono(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: active
                          ? ExodoColors.amber
                          : (isLight ? const Color(0xFF171615) : Colors.white),
                    ),
                  ),
                  Text(
                    m.subtitle,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      color: active
                          ? ExodoColors.amber
                          : (isLight ? Colors.black54 : Colors.white70),
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
                                  ? const Color(0xFFEFECE4)
                                  : const Color(0xFF3A352F)),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: active
                              ? ExodoColors.amber
                              : (isLight ? Colors.black12 : Colors.white24),
                        ),
                      ),
                      child: Text(
                        'PRO',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: active
                              ? ExodoColors.amber
                              : (isLight
                                    ? const Color(0xFF33302C)
                                    : Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                AppI18n.of(context).t('models.${m.id}_desc'),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: active
                      ? ExodoColors.amber
                      : (isLight ? Colors.black54 : Colors.white70),
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
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: isLight ? Colors.black54 : ExodoColors.textSecondary,
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

class _PulsingXpiAura extends StatefulWidget {
  final Widget child;
  const _PulsingXpiAura({required this.child});
  @override
  State<_PulsingXpiAura> createState() => _PulsingXpiAuraState();
}

class _PulsingXpiAuraState extends State<_PulsingXpiAura>
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

class _UpgradeModal {
  static void show(BuildContext context) {
    HapticFeedback.vibrate();
    bool isAnnual = false;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bgColor = isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1C1C1E);
    final surfaceColor = isLight
        ? const Color(0xFFF2F2F7)
        : const Color(0xFF2C2C2E);
    final composerBg = isLight
        ? const Color(0xFFF2F2F7)
        : const Color(0xFF2C2C2E);
    final borderColor = isLight
        ? const Color(0xFFD1D1D6)
        : const Color(0xFF3A3A3C);
    final textPrimary = isLight
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    final textSecondary = isLight
        ? const Color(0xFF8E8E93)
        : const Color(0xFF8E8E93);
    final radioOff = isLight
        ? const Color(0xFFC7C7CC)
        : const Color(0xFF48484A);
    final buttonBg = isLight
        ? const Color(0xFF000000)
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
          child: Padding(
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
                        style: GoogleFonts.syne(
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
                        style: GoogleFonts.syne(
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
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: !isAnnual ? surfaceColor : bgColor,
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
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: textPrimary,
                                      ),
                                    ),
                                    Text(
                                      AppI18n.of(
                                        context,
                                      ).t('billing.billed_monthly'),
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => isAnnual = true),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isAnnual ? surfaceColor : bgColor,
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
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: ExodoColors.amber.withValues(
                                              alpha: 0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
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
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '\$49.99',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: textPrimary,
                                      ),
                                    ),
                                    Text(
                                      AppI18n.of(
                                        context,
                                      ).t('billing.billed_annually'),
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
        children: [
          Icon(Icons.check, size: 15, color: color),
          const SizedBox(width: 8),
          Text(text, style: GoogleFonts.inter(fontSize: 12.5, color: color)),
        ],
      ),
    );
  }
}

/// Wrapper interno para usar ScrollToBottomButton dentro de chat_screen.
/// Maneja la lógica de "mostrar solo cuando hay suficientes mensajes".
class _ScrollToBottomHost extends StatefulWidget {
  final ScrollController controller;
  final int messagesCount;
  const _ScrollToBottomHost({
    required this.controller,
    required this.messagesCount,
  });

  @override
  State<_ScrollToBottomHost> createState() => _ScrollToBottomHostState();
}

class _ScrollToBottomHostState extends State<_ScrollToBottomHost> {
  @override
  Widget build(BuildContext context) {
    return ScrollToBottomButton(
      controller: widget.controller,
      messagesCount: widget.messagesCount,
    );
  }
}
