import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_state.dart';
import '../services/widget_service.dart';
import '../widgets/drawer_menu.dart';
import '../widgets/scroll_to_bottom_button.dart';
import '../widgets/chat/chat_app_bar.dart';
import '../widgets/chat/chat_stage.dart';
import '../widgets/chat/chat_composer.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/model_selector.dart';
import '../theme/exodo_theme.dart';
import '../l10n/app_i18n.dart';

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
      builder: (_) => const ModelSelectorSheet(),
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
                          final lastAssistantIndex = state.currentMessages
                              .lastIndexWhere((m) => m.role == 'assistant');
                          return ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              top: 8,
                              bottom: 200,
                            ),
                            itemCount: state.currentMessages.length,
                            itemBuilder: (context, index) {
                              final msg = state.currentMessages[index];
                              if (msg.isThinking) {
                                return ThinkingBubble(pulseAnim: _pulseCtrl);
                              }
                              return MessageBubble(
                                message: msg,
                                isLastAssistant: index == lastAssistantIndex,
                              );
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
                              UpgradeModal.show(context);
                            }
                            state.sendUserMessage(text);
                            return;
                          }
                          _inputCtrl.clear();
                          state.sendUserMessage(text, attachments: attachments);
                        },
                        onModelTap: _showModelSheet,
                        onUpgradeTap: () => UpgradeModal.show(context),
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
                        UpgradeModal.show(context);
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
