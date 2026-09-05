import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../widgets/chat/image_generating_placeholder.dart';
import '../services/chat_service.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../services/context_export_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/exodo_theme.dart';
import '../l10n/app_i18n.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _ageGateChecked = false;

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
    // [Fix LG V60 #3 / #482] FLAG_SECURE en Modo Incógnito: bloquea capturas
    // y miniatura en multitarea; se apaga al volver al modo normal.
    state.addListener(_syncFlagSecure);
    // [Fix LG V60 #5] Al citar texto ("Preguntar a Éxodo"), el chat baja al
    // final para que composer + chip de cita queden a la vista con teclado.
    state.onRequestChatScrollToBottom = _scrollChatToBottom;
    _syncAnimations();
    _syncFlagSecure();

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

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowConsentGate());
  }

  /// CONSENTIMIENTO inicial (30-ago, estilo contrato): una sola vez tras el
  /// primer login con Google. Dos casillas: edad 13+ y historial en nube.
  /// Se guarda registro local con fecha + best-effort en profiles
  /// (protege a Behavior: el usuario aceptó explícitamente). Si la cuenta se
  /// borra o se cierra sesión, el registro se limpia y vuelve a preguntar.
  static bool _consentGateShownThisRun = false;

  Future<void> _maybeShowConsentGate() async {
    if (_ageGateChecked || _consentGateShownThisRun || !mounted) return;
    final state = context.read<AppState>();
    if (state.isGuestUser || !state.hasSession) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('exodo_age_confirmed') == true) {
      _ageGateChecked = true;
      return;
    }
    _ageGateChecked = true;
    _consentGateShownThisRun = true;
    // FIX doble-diálogo: escribir el flag ANTES de mostrar. Si un remount de
    // ChatScreen ocurre mientras el diálogo está abierto, el nuevo estado ya
    // lo ve confirmado y no lo repite. (El consentimiento real queda registrado
    // al aceptar: nube + registro local con fecha.)
    await prefs.setBool('exodo_age_confirmed', true);
    if (!mounted) return;
    bool ageOk = false;
    bool cloudOk = true; // default: sí guardar (comportamiento histórico)
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).brightness == Brightness.light
              ? Colors.white : const Color(0xFF1E1E1E),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _consentRow(ctx, setDialogState, () => ageOk, (v) { ageOk = v; }, AppI18n.of(context).t('consent.age')),
              const SizedBox(height: 12),
              _consentRow(ctx, setDialogState, () => cloudOk, (v) { cloudOk = v; }, AppI18n.of(context).t('consent.cloud')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: ageOk
                  ? () async {
                      final ts = DateTime.now().toUtc().toIso8601String();
                      await prefs.setString('exodo_consent', '{"age":true,"cloud":$cloudOk,"ts":"$ts","v":1}');
                      await state.setCloudHistoryEnabled(cloudOk);
                      // Momento ideal para pedir notificaciones: interacción
                      // real en primer plano (Android 13+ lo exige).
                      unawaited(NotificationService.instance.ensurePermission());
                      // Registro en la nube, best-effort (protección mutua)
                      try {
                        final uid = SupabaseService.client.auth.currentUser?.id;
                        if (uid != null) {
                          final existing = (state.profile?.onboarding is Map)
                              ? Map<String, dynamic>.from(state.profile!.onboarding as Map)
                              : <String, dynamic>{};
                          existing['age_confirmed'] = true;
                          existing['cloud_history_consent'] = cloudOk;
                          existing['consent_ts'] = ts;
                          await SupabaseService.saveOnboarding(existing);
                        }
                      } catch (_) {}
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  : null,
              child: Text(
                AppI18n.of(context).t('age.continue'),
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _consentRow(BuildContext ctx, void Function(void Function()) setDialog, bool Function() getVal, void Function(bool) setVal, String label) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setDialog(() => setVal(!getVal()));
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            getVal() ? Icons.check_box : Icons.check_box_outline_blank,
            size: 20,
            color: getVal() ? ExodoColors.amber : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: GoogleFonts.inter(fontSize: 13.5, height: 1.4)),
          ),
        ],
      ),
    );
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
    _observedState?.removeListener(_syncFlagSecure);
    _observedState?.onRequestChatScrollToBottom = null;
    WidgetsBinding.instance.removeObserver(this);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _followBottomNotifier.dispose();
    _ambientBgCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  /// [Fix LG V60 #5] Baja el chat al último mensaje cuando se fija una cita
  /// ("Preguntar a Éxodo"): el chip y el composer quedan a la vista.
  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  static const _windowChannel = MethodChannel('exodo/window');
  bool _flagSecureActive = false;

  /// [Fix LG V60 #3 / #482] Sincroniza FLAG_SECURE con el Modo Incógnito:
  /// activa la ventana segura al entrar y la libera al salir. Solo invoca el
  /// canal nativo cuando cambia el estado (los notifies son frecuentes).
  void _syncFlagSecure() {
    final incognito = _observedState?.isIncognito ?? false;
    if (incognito == _flagSecureActive) return;
    _flagSecureActive = incognito;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _windowChannel.invokeMethod('setSecure', {'secure': incognito});
      } catch (_) {
        // Plataforma sin el canal (web/Windows): la privacidad del modo
        // incógnito no depende de FLAG_SECURE para funcionar.
      }
    });
  }

  void _showModelSheet() {
    // [Punto 6] Incógnito E invitado: la hoja no abre; sólo háptica sutil.
    final appState = context.read<AppState>();
    if (appState.isIncognito || appState.isGuestUser) {
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

  Widget _buildChatComposer() {
    return ChatComposer(
      key: const ValueKey('chat_composer'),
      controller: _inputCtrl,
      onSend: (attachments) {
        final text = _inputCtrl.text;
        final state = context.read<AppState>();
        if (text.trim().isEmpty &&
            (attachments == null || attachments.isEmpty) &&
            (state.quotedSnippet == null || state.quotedSnippet!.isEmpty)) {
          return;
        }
        FocusScope.of(context).unfocus();
        if (state.editingMessage != null) {
          final msgToEdit = state.editingMessage!;
          state.cancelEditingMessage();
          _inputCtrl.clear();
          state.editAndRegenerateUserMessage(msgToEdit, text);
          return;
        }
        // FIX cajón + planes: el cajón se limpia SIEMPRE al enviar (antes la
        // rama de cuota retornaba sin _inputCtrl.clear() y el texto enviado
        // quedaba pegado en el composer). Y enviar JAMÁS abre Planes: el
        // backend es soft-cap (degrada a Modo Eco, nunca 429 por tokens), así
        // que el gate local con estimador (length~/3) solo producía falsos
        // positivos — modal en cada envío en free/pro/incógnito una vez que
        // el contador local tocaba el tope. La cuota real la informa el
        // servidor (isDegraded → eco-notice) y el medidor de Billing.
        _inputCtrl.clear();
        state.sendUserMessage(text, attachments: attachments);
      },
      onModelTap: _showModelSheet,
      onUpgradeTap: () {
        // [Punto 6] Invitado: no-op silencioso con háptica
        // suave; nunca abre el modal de compra.
        if (context.read<AppState>().isGuestUser) {
          HapticFeedback.selectionClick();
          return;
        }
        UpgradeModal.show(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // [Fix rendimiento streaming] Este build() ahora usa context.select en
    // vez de context.watch. Solo se reconstruye cuando isDarkMode, isIncognito,
    // hasMessages u isOnline cambian — NO cada vez que llega un chunk SSE (que muta
    // currentMessages). El chat en sí vive en ChatMessagesList, que tiene
    // su propia suscripción aislada a AppState y no le pega al Scaffold.
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);
    final hasMessages = context.select<AppState, bool>((s) => s.currentMessages.isNotEmpty);
    final isLight = !isDarkMode && !isIncognito;
    final isIncognitoCentered = isIncognito && !hasMessages;

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

              // Auto-update APK: banner visible y persistente cuando hay una
              // versión nueva ya descargada (los instalados fuera de Play
              // Store no se actualizan solos; la notificación del sistema se
              // pierde fácil — esto lo pone en pantalla hasta instalar).
              const _UpdateReadyBanner(),


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
                    if (!isIncognitoCentered) ...[
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
                      // Barra inferior entrelazada del Tab 1 (fijada abajo cuando hay mensajes o en modo normal)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _buildChatComposer(),
                      ),
                    ] else ...[
                      // Modo Incógnito vacío: Cajón medio a medio con el disclaimer (paridad web)
                      Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          physics: const ClampingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
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
                              ),
                              const SizedBox(height: 28),
                              _buildChatComposer(),
                            ],
                          ),
                        ),
                      ),
                    ],
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
      if (state.isIncognito) {
        // En modo incógnito vacío, el disclaimer y el composer se renderizan
        // centrados en el Stack de ChatScreen ("medio a medio", paridad web).
        return const SizedBox.shrink();
      }
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
        itemCount: state.currentMessages.length + (state.currentMessages.length >= 40 && !state.isGenerating ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.currentMessages.length) {
            // Límite de contexto inteligente: 40 mensajes = ventana de 25 ya
            // recortando el inicio; 60 = urgente (instrucciones de 3 puntos).
            return _LongConversationBanner(
              urgent: state.currentMessages.length >= 60,
              onNewChat: () => state.startNewChat(),
              onExport: () => _exportConversationContext(context, state),
            );
          }
          final msg = state.currentMessages[index];
          if (msg.isThinking) {
            return RepaintBoundary(
              key: ValueKey('thinking-${msg.id}'),
              child: state.isGeneratingImage
                  ? const ImageGeneratingPlaceholder()
                  : ThinkingBubble(pulseAnim: widget.pulseAnim),
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


/// Aviso de límite de contexto, estilo disclaimer (texto tenue, sin tarjeta):
/// mismo lenguaje visual que "Éxodo es IA y puede cometer errores" — discreto,
/// elegante y no invasivo. A los 40 mensajes avisa; a los 60 añade acciones
/// inline (Exportar contexto · Nuevo chat) y el texto de los 3 pasos.
class _LongConversationBanner extends StatefulWidget {
  final bool urgent;
  final VoidCallback onNewChat;
  final VoidCallback onExport;

  const _LongConversationBanner({
    this.urgent = false,
    required this.onNewChat,
    required this.onExport,
  });

  @override
  State<_LongConversationBanner> createState() => _LongConversationBannerState();
}

class _LongConversationBannerState extends State<_LongConversationBanner> {
  @override
  Widget build(BuildContext context) {
    final t = AppI18n.of(context).t;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textCol = isLight ? Colors.black : ExodoColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Column(
        children: [
          Opacity(
            opacity: 0.5,
            child: Text(
              widget.urgent ? t('banner.context_limit_urgent') : t('banner.long_conversation'),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                height: 1.35,
                color: textCol,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onExport();
                },
                child: Opacity(
                  opacity: 0.65,
                  child: Text(
                    t('banner.export_context'),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      color: textCol,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Opacity(
                  opacity: 0.35,
                  child: Text('·', style: TextStyle(fontSize: 11, color: textCol)),
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onNewChat();
                },
                child: Opacity(
                  opacity: 0.65,
                  child: Text(
                    t('banner.new_chat'),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      color: textCol,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Exporta el contexto del chat activo como HTML reimportable y abre el
/// Share Sheet nativo (guardar, enviar, etc.). Usado por el banner de límite.
Future<void> _exportConversationContext(BuildContext context, AppState state) async {
  final t = AppI18n.of(context).t;
  await ContextExportService.exportAndShare(
    title: state.activeConversation?.title ?? t('banner.context_default_title'),
    locale: state.effectiveLocale,
    messages: state.currentMessages,
    transcriptLabel: t('banner.context_transcript'),
    roleUserLabel: t('banner.context_role_user'),
    roleAiLabel: t('banner.context_role_ai'),
    reimportHint: t('banner.context_reimport_hint'),
  );
}



/// Banner persistente de auto-update (APK directo fuera de Play Store):
/// aparece cuando UpdateService ya descargó el APK nuevo en segundo plano.
/// El tap lanza el instalador del sistema (único paso que exige Android).
/// Sin esto, los instalados seguían en la versión con los bugs del cajón
/// y del modal de planes porque la notificación se descartaba.
class _UpdateReadyBanner extends StatelessWidget {
  const _UpdateReadyBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: UpdateService.instance.readyToInstall,
      builder: (context, apkPath, _) {
        if (apkPath == null) return const SizedBox.shrink();
        final info = UpdateService.instance.pendingInfo;
        final versionLabel = (info?.versionName.isNotEmpty ?? false)
            ? ' v${info!.versionName}'
            : '';
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.mediumImpact();
              UpdateService.instance.install();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: ExodoColors.amber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: ExodoColors.amber.withValues(alpha: 0.45),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.system_update_rounded,
                    size: 20,
                    color: ExodoColors.amber,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${AppI18n.of(context).t('notification.update_ready_body')}$versionLabel',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: ExodoColors.amber,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: ExodoColors.amber,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
