import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/widget_service.dart';
import '../widgets/drawer_menu.dart';
import '../widgets/scroll_to_bottom_button.dart';
import '../widgets/chat/chat_app_bar.dart';
import '../widgets/chat/chat_stage.dart';
import '../widgets/chat/chat_composer.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/model_selector.dart';
import '../services/chat_service.dart';
import '../services/tts_service.dart';
import '../theme/exodo_theme.dart';

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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // [TASK 3] App minimizada o inactiva: cancelar TTS y grabación
      TtsService.instance.stop();
      // [Sprint 0] pausar animaciones para ahorrar batería.
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
    ChatService.cancelStream();
    WidgetsBinding.instance.removeObserver(this);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _thinkingAnimCtrl.dispose();
    _ambientBgCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _showModelSheet() {
    if (context.read<AppState>().isIncognito) {
      HapticFeedback.selectionClick();
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark
          ? ExodoColors.background
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const ModelSelectorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // [Fix rendimiento streaming] Este build() ahora usa context.select en
    // vez de context.watch. Solo se reconstruye cuando isDarkMode, isIncognito
    // u isOnline cambian — NO cada vez que llega un chunk SSE (que muta
    // currentMessages). El chat en sí vive en ChatMessagesList, que tiene
    // su propia suscripción aislada a AppState y no le pega al Scaffold.
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);
    final isLight = !isDarkMode && !isIncognito;

    return Scaffold(
      drawer: const DrawerMenu(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.26,
      onDrawerChanged: (isOpened) {
        if (isOpened && isIncognito) {
          context.read<AppState>().exitIncognitoAndClear();
        }
      },
      body: AnimatedAmbientBackground(
        animation: _ambientBgCtrl,
        child: SafeArea(
          child: Column(
            children: [
              // Barra superior minimalista y limpia modularizada
              const ChatAppBar(),


              // Stage principal o lista de mensajes (SIEMPRE VISIBLE y fluye tras el composer)
              Expanded(
                child: Stack(
                  children: [
                    // [Fix rendimiento streaming] Todo el contenido que depende
                    // de currentMessages/isGenerating vive aislado aquí dentro.
                    ChatMessagesList(
                      scrollCtrl: _scrollCtrl,
                      pulseAnim: _pulseCtrl,
                      isLight: isLight,
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
                                        ? ExodoColors.textPrimary
                                        : ExodoColors.chatBg)
                                    .withValues(alpha: 0.0),
                                (isLight
                                        ? ExodoColors.textPrimary
                                        : ExodoColors.chatBg)
                                    .withValues(alpha: 0.85),
                                (isLight
                                    ? ExodoColors.textPrimary
                                    : ExodoColors.chatBg),
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
                      child: _ScrollToBottomHostSelector(
                        controller: _scrollCtrl,
                      ),
                    ),
                    // Floating Stop Pill - muestra solo cuando TTS está hablando
                    Positioned(
                      bottom: 85,
                      left: 24,
                      right: 24,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: TtsService.instance.isSpeakingNotifier,
                        builder: (context, isSpeaking, _) {
                          if (!isSpeaking) return const SizedBox.shrink();
                          return Material(
                            elevation: 12,
                            borderRadius: BorderRadius.circular(28),
                            color: const Color(0xFF1B1B1E),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  const Icon(Icons.graphic_eq_rounded, color: Colors.amberAccent, size: 22),
                                  const SizedBox(width: 10),
                                  const Text('Éxodo leyendo...', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () => TtsService.instance.stop(),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                      child: const Icon(Icons.stop_rounded, color: Colors.white, size: 20),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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
                          if (text.trim().isEmpty &&
                              (attachments == null || attachments.isEmpty)) {
                            return;
                          }
                          FocusScope.of(context).unfocus();
                          final state = context.read<AppState>();
                          if (!state.isGuestUser &&
                              (state.tokensUsed >= state.tokensLimit ||
                                  state.tokensUsed + (text.length ~/ 3) + 15 >
                                      state.tokensLimit)) {
                            HapticFeedback.vibrate();
                            if (!state.isPro) {
                              UpgradeModal.show(context);
                            }
                            state.sendUserMessage(
                              text,
                              attachments: attachments,
                            );
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

/// [Fix rendimiento streaming] Widget aislado que contiene TODO lo que
/// depende de currentMessages y isGenerating. Su propio `context.watch<AppState>()`
/// vive aquí, no en _ChatScreenState.build(), así que cuando llega un chunk SSE
/// solo ESTE subárbol se reconstruye — ChatAppBar, el degradado, el botón de
/// scroll y el composer del padre quedan intactos y no repintan nada de más.
class ChatMessagesList extends StatefulWidget {
  final ScrollController scrollCtrl;
  final AnimationController pulseAnim;
  final bool isLight;

  const ChatMessagesList({
    super.key,
    required this.scrollCtrl,
    required this.pulseAnim,
    required this.isLight,
  });

  @override
  State<ChatMessagesList> createState() => _ChatMessagesListState();
}

class _ChatMessagesListState extends State<ChatMessagesList> {
  int _lastMessageCount = 0;
  bool _followStreamingBottom = true;

  void _scrollToBottom() {
    _followStreamingBottom = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.scrollCtrl.hasClients) {
        widget.scrollCtrl.animateTo(
          widget.scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Este watch queda AISLADO a este widget. Cuando currentMessages cambia
    // (cada chunk), solo este subárbol reconstruye, no el Scaffold del padre.
    final state = context.watch<AppState>();

    if (state.currentMessages.length > _lastMessageCount) {
      _lastMessageCount = state.currentMessages.length;
      _followStreamingBottom = true;
      _scrollToBottom();
    } else {
      _lastMessageCount = state.currentMessages.length;
      if (_followStreamingBottom && state.isGenerating) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_followStreamingBottom &&
              state.isGenerating &&
              widget.scrollCtrl.hasClients) {
            if (widget.scrollCtrl.position.extentAfter > 2) {
              widget.scrollCtrl.jumpTo(
                widget.scrollCtrl.position.maxScrollExtent,
              );
            }
          }
        });
      }
    }

    if (state.currentMessages.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 120),
          physics: const ClampingScrollPhysics(),
          child: ChatStage(
            pulseAnim: widget.pulseAnim,
            fullName: state.profile?.fullName,
          ),
        ),
      );
    }

    // [Punto 36 aviso] Filtro defensivo: aunque currentMessages
    // tenga contenido, si NO hay conversación activa seleccionada
    // Y NO hay un mensaje del usuario en la lista, mostramos el
    // stage vacío en lugar de mensajes residuales.
    final hasUserMsg = state.currentMessages.any((m) => m.role == 'user');
    final hasActiveConv = state.activeConversation != null;
    if (!hasUserMsg && !hasActiveConv && !state.isIncognito) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 120),
          physics: const ClampingScrollPhysics(),
          child: ChatStage(
            pulseAnim: widget.pulseAnim,
            fullName: state.profile?.fullName,
          ),
        ),
      );
    }

    final lastAssistantIndex = state.currentMessages.lastIndexWhere(
      (m) => m.role == 'assistant',
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _followStreamingBottom = false;
        } else if (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) {
          _followStreamingBottom = false;
        } else if (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle &&
            widget.scrollCtrl.position.isScrollingNotifier.value) {
          _followStreamingBottom = false;
        }
        return false;
      },
      child: ListView.builder(
        controller: widget.scrollCtrl,
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
            return RepaintBoundary(
              key: ValueKey('thinking-${msg.id}'),
              child: ThinkingBubble(pulseAnim: widget.pulseAnim),
            );
          }
          return RepaintBoundary(
            key: ValueKey(msg.id),
            child: MessageBubble(
              message: msg,
              isLastAssistant: index == lastAssistantIndex,
            ),
          );
        },
      ),
    );
  }
}



/// [Fix rendimiento streaming] Este wrapper ahora usa su propio
/// context.select para leer solo currentMessages.length, sin arrastrar
/// al padre (_ChatScreenState) a reconstruirse en cada chunk.
class _ScrollToBottomHostSelector extends StatelessWidget {
  final ScrollController controller;
  const _ScrollToBottomHostSelector({
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final messagesCount = context.select<AppState, int>(
      (s) => s.currentMessages.length,
    );
    return ScrollToBottomButton(
      controller: controller,
      messagesCount: messagesCount,
    );
  }
}
