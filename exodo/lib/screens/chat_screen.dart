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
  final _followBottomNotifier = ValueNotifier<bool>(true);
  // P3 batería: los controladores NO repiten en initState. Se encienden solo
  // mientras hay generación activa (isGenerating) y se detienen al terminar.
  // Antes animaban 24/7 en primer plano aunque la pantalla estuviera quieta.
  late AnimationController _ambientBgCtrl;
  late AnimationController _pulseCtrl;
  AppState? _observedState;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    _ambientBgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
    // Regla 5 & 9: Pulso continuo para cambio de tamaño de puntos aleatorio
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    final state = context.read<AppState>();
    _observedState = state;
    state.addListener(_syncAnimations);
    _syncAnimations();

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

  void _syncAnimations() {
    if (!mounted) return;
    final generating = context.read<AppState>().isGenerating;
    if (generating) {
      if (!_ambientBgCtrl.isAnimating) _ambientBgCtrl.repeat(reverse: true);
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
    } else {
      _ambientBgCtrl.stop();
      _pulseCtrl.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // App minimizada, oculta o inactiva: pausar animaciones
      _ambientBgCtrl.stop();
      _pulseCtrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      // App vuelve a primer plano: reanudar solo si corresponde (isGenerating).
      _syncAnimations();
      // P3 monetización: si el usuario volvió de la pasarela de pago (Stripe
      // en el navegador), revalidar el plan sin reiniciar la app.
      context.read<AppState>().refreshProfileFromCloud();
    }
  }

  @override
  void dispose() {
    ChatService.cancelStream();
    _observedState?.removeListener(_syncAnimations);
    WidgetsBinding.instance.removeObserver(this);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _followBottomNotifier.dispose();
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
        if (isOpened) {
          context.read<AppState>().cancelActiveVoiceRecording();
          if (isIncognito) {
            context.read<AppState>().exitIncognitoAndClear();
          }
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
                      followBottomNotifier: _followBottomNotifier,
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
                        followBottomNotifier: _followBottomNotifier,
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
                          if (state.editingMessage != null) {
                            final msgToEdit = state.editingMessage!;
                            state.cancelEditingMessage();
                            _inputCtrl.clear();
                            state.editAndRegenerateUserMessage(msgToEdit, text);
                            return;
                          }
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
  final ValueNotifier<bool> followBottomNotifier;

  const ChatMessagesList({
    super.key,
    required this.scrollCtrl,
    required this.pulseAnim,
    required this.isLight,
    required this.followBottomNotifier,
  });

  @override
  State<ChatMessagesList> createState() => _ChatMessagesListState();
}

class _ChatMessagesListState extends State<ChatMessagesList> {
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    widget.followBottomNotifier.addListener(_onFollowToggled);
  }

  @override
  void didUpdateWidget(covariant ChatMessagesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.followBottomNotifier != widget.followBottomNotifier) {
      oldWidget.followBottomNotifier.removeListener(_onFollowToggled);
      widget.followBottomNotifier.addListener(_onFollowToggled);
    }
  }

  @override
  void dispose() {
    widget.followBottomNotifier.removeListener(_onFollowToggled);
    super.dispose();
  }

  void _onFollowToggled() {
    if (widget.followBottomNotifier.value) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.scrollCtrl.hasClients) {
        widget.scrollCtrl.animateTo(
          widget.scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
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
      widget.followBottomNotifier.value = true;
      _scrollToBottom();
    } else {
      _lastMessageCount = state.currentMessages.length;
      if (widget.followBottomNotifier.value && state.isGenerating) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (widget.followBottomNotifier.value &&
              state.isGenerating &&
              widget.scrollCtrl.hasClients) {
            if (widget.scrollCtrl.position.extentAfter > 1) {
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
        if (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.forward &&
            notification.metrics.extentBefore > 40) {
          // El usuario scrolleó hacia arriba: desanclar seguimiento automático
          if (widget.followBottomNotifier.value) {
            widget.followBottomNotifier.value = false;
          }
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
        itemCount: state.currentMessages.length + (state.currentMessages.length >= 24 && !state.isGenerating ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.currentMessages.length) {
            return _LongConversationBanner(
              isLight: widget.isLight,
              onNewChat: () => state.startNewChat(),
            );
          }
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

/// Banner preventivo estilo Claude cuando la conversación acumula muchos turnos
class _LongConversationBanner extends StatefulWidget {
  final bool isLight;
  final VoidCallback onNewChat;

  const _LongConversationBanner({
    required this.isLight,
    required this.onNewChat,
  });

  @override
  State<_LongConversationBanner> createState() => _LongConversationBannerState();
}

class _LongConversationBannerState extends State<_LongConversationBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isLight ? const Color(0xFFF7F5EE) : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isLight
              ? const Color(0xFFE2DCD2)
              : const Color(0xFF333336),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            size: 18,
            color: ExodoColors.amber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Esta conversación es extensa. Para consultas complejas o máxima retención de contexto, considera iniciar un nuevo chat.',
              style: TextStyle(
                fontFamily: 'AnthropicSans',
                fontSize: 12,
                color: widget.isLight ? const Color(0xFF555555) : Colors.white70,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onNewChat();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: ExodoColors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Nuevo',
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: ExodoColors.amber,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: widget.isLight ? Colors.black45 : Colors.white38,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () {
              setState(() => _dismissed = true);
            },
          ),
        ],
      ),
    );
  }
}



/// [Fix rendimiento streaming] Este wrapper ahora usa su propio
/// context.select para leer solo currentMessages.length, sin arrastrar
/// al padre (_ChatScreenState) a reconstruirse en cada chunk.
class _ScrollToBottomHostSelector extends StatelessWidget {
  final ScrollController controller;
  final ValueNotifier<bool> followBottomNotifier;
  const _ScrollToBottomHostSelector({
    required this.controller,
    required this.followBottomNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final messagesCount = context.select<AppState, int>(
      (s) => s.currentMessages.length,
    );
    return ScrollToBottomButton(
      controller: controller,
      messagesCount: messagesCount,
      onPressed: () {
        followBottomNotifier.value = true;
      },
    );
  }
}
