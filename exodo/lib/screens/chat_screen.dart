import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/supabase_service.dart';
import '../services/tts_service.dart';
import '../widgets/drawer_menu.dart';
import '../widgets/scroll_to_bottom_button.dart';
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

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late AnimationController _thinkingAnimCtrl;
  late AnimationController _ambientBgCtrl;
  late AnimationController _pulseCtrl;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _thinkingAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _ambientBgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat(reverse: true);
    // Regla 5 & 9: Pulso continuo para cambio de tamaño de puntos aleatorio
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);

  }

  @override
  void dispose() {
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
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _showModelSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? ExodoColors.modelChipBg : Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
      body: _AnimatedAmbientBackground(
        animation: _ambientBgCtrl,
        child: SafeArea(
          child: Column(
            children: [
              // Barra superior minimalista y limpia
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                              Container(width: 20, height: 2, decoration: BoxDecoration(color: isLight ? Colors.black87 : ExodoColors.textPrimary, borderRadius: BorderRadius.circular(1))),
                              const SizedBox(height: 5),
                              Container(width: 20, height: 2, decoration: BoxDecoration(color: isLight ? Colors.black87 : ExodoColors.textPrimary, borderRadius: BorderRadius.circular(1))),
                              const SizedBox(height: 5),
                              Container(width: 12, height: 2, decoration: BoxDecoration(color: isLight ? Colors.black87 : ExodoColors.textPrimary, borderRadius: BorderRadius.circular(1))),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const Spacer(),

                    // En modo incógnito quitar iconos New Chat y Dark Mode
                    if (!state.isIncognito) ...[
                      // 1. Nuevo Chat
                      IconButton(
                        icon: Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 21,
                          color: isLight ? Colors.black87 : ExodoColors.textSecondary,
                        ),
                        tooltip: 'Nuevo chat',
                        onPressed: () => state.startNewChat(),
                      ),

                      // 2. Dark / Light Mode
                      IconButton(
                        icon: Icon(
                          state.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                          size: 22,
                          color: isLight ? Colors.black87 : ExodoColors.textSecondary,
                        ),
                        tooltip: 'Cambiar tema',
                        onPressed: () => state.toggleTheme(),
                      ),
                    ],

                    // 3. Incógnito (botón para activarlo o salir)
                    IconButton(
                      icon: _AnimatedIncognitoHat(
                        isIncognito: state.isIncognito,
                        child: Image.asset(
                          'assets/images/incognito-svgrepo-com.png',
                          width: 22,
                          height: 22,
                          color: state.isIncognito ? Colors.white : (isLight ? Colors.black87 : ExodoColors.textSecondary),
                        ),
                      ),
                      tooltip: _isDeviceEnglish(context) ? 'Incognito mode' : 'Modo incógnito',
                      onPressed: () {
                        state.toggleIncognito();
                      },
                    ),
                  ],
                ),
              ),

              // Regla 4: Conteo de tokens (desaparece en modo incógnito y modo Guest)
              if (!state.isIncognito && !state.isGuestUser)
                _TokenProgressBar(
                  used: state.tokensUsed,
                  limit: state.tokensLimit,
                  resetTime: state.tokensResetTime,
                  isPro: state.isPro,
                ),

              // Stage principal o lista de mensajes (Regla 8)
              // Stage principal o lista de mensajes (SIEMPRE VISIBLE)
              Expanded(
                child: Stack(
                  children: [
                    if (state.currentMessages.isEmpty)
                      Center(
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: _OriginalDesignStage(
                            pulseAnim: _pulseCtrl,
                            fullName: state.profile?.fullName,
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: state.currentMessages.length,
                        itemBuilder: (context, index) {
                          final msg = state.currentMessages[index];
                          if (msg.isThinking) {
                            return _ThinkingBubble(pulseAnim: _pulseCtrl);
                          }
                          return _MessageBubble(message: msg);
                        },
                      ),
                    // Botón flotante "scroll to bottom" (esquina inferior derecha).
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: _ScrollToBottomHost(
                        controller: _scrollCtrl,
                        messagesCount: state.currentMessages.length,
                      ),
                    ),
                  ],
                ),
              ),

              // Barra inferior entrelazada del Tab 1 (SIEMPRE en su sitio exacto)
              _InterlockingComposerArea(
                controller: _inputCtrl,
                onSend: () {
                    final text = _inputCtrl.text;
                    if (text.trim().isEmpty) return;
                    FocusScope.of(context).unfocus();
                    if (!state.isGuestUser && (state.tokensUsed >= state.tokensLimit || state.tokensUsed + (text.length ~/ 3) + 15 > state.tokensLimit)) {
                      HapticFeedback.vibrate();
                      if (!state.isPro) {
                        _UpgradeModal.show(context);
                      }
                      state.sendUserMessage(text);
                      return;
                    }
                    _inputCtrl.clear();
                    state.sendUserMessage(text);
                  },
                  onModelTap: _showModelSheet,
                ),
            ],
          ),
        ),
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

class _AnimatedIncognitoHatState extends State<_AnimatedIncognitoHat> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _anim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0).chain(CurveTween(curve: Curves.easeOutQuad)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 0.0).chain(CurveTween(curve: Curves.bounceOut)), weight: 60),
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
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _anim.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// Regla 2 & 7: Fondo ambiental sólido (sin animación) con watermark según modo
class _AnimatedAmbientBackground extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _AnimatedAmbientBackground({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final isDarkBg = state.isDarkMode || state.isIncognito;
    final bgColor = isDarkBg ? const Color(0xFF20201F) : const Color(0xFFFBF9F5);

    // La watermark ahora vive dentro de _OriginalDesignStage para garantizar
    // que saludo y PNG nunca choquen (Spacer flexible entre ambos).
    return Container(
      color: bgColor,
      child: child,
    );
  }
}

class _OriginalDesignStage extends StatelessWidget {
  final Animation<double> pulseAnim;
  final String? fullName;
  const _OriginalDesignStage({required this.pulseAnim, required this.fullName});

  String _getGreeting(BuildContext context, AppState state) {
    final isEn = _isDeviceEnglish(context);
    final temp = state.currentTempC;

    if (temp != null) {
      if (temp <= 21.0) {
        return isEn ? 'Cold outside, better than coffee' : 'Frío afuera, mejor que un café';
      } else if (temp >= 31.0) {
        return isEn ? 'Grab something cold, really hot' : 'Toma algo frío, hace mucho calor';
      }
    }

    final hour = DateTime.now().hour;
    if (isEn) {
      if (hour >= 0 && hour < 6) return 'Late night hustle';
      if (hour < 12) return 'Morning';
      if (hour < 18) return 'Afternoon';
      return 'Evening';
    } else {
      if (hour >= 0 && hour < 6) return 'Ni la madrugada te detiene';
      if (hour < 12) return 'Cafecito con Exodo';
      if (hour < 18) return 'Tarde productiva';
      return 'La noche es joven';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = Theme.of(context).brightness == Brightness.light && !state.isIncognito;
    final isEn = _isDeviceEnglish(context);

    final isDarkBg = state.isDarkMode || state.isIncognito;
    final watermarkAsset = isDarkBg ? 'assets/images/watermark2.png' : 'assets/images/watermark1.png';

    // ============================================================
    // LAYOUT CENTRADO: saludo + watermark como bloque único vertical.
    // Ambos se centran juntos en la pantalla. La watermark va justo
    // debajo del saludo (separación fija de 16px). Cero Spacer, cero
    // LayoutBuilder –” el Center hace todo el trabajo.
    // ============================================================

    // Watermark: ancho 40% del stage, aspect ratio real 7.0208 (1011x144)
    final stageWidth = MediaQuery.of(context).size.width;
    final watermarkWidth = stageWidth * 0.40;
    final watermarkHeight = watermarkWidth / 7.0208;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Saludo (original, máximo 2 líneas)
            Text(
              state.isIncognito
                  ? (isEn ? 'Incognito' : 'Incógnito')
                  : _getGreeting(context, state),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isLight ? const Color(0xFF171615) : Colors.white,
                height: 1.15,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),
            // Watermark: segunda línea, justo debajo del saludo
            IgnorePointer(
              child: SizedBox(
                width: watermarkWidth,
                height: watermarkHeight,
                child: Image.asset(
                  watermarkAsset,
                  fit: BoxFit.fill,
                ),
              ),
            ),
            if (state.isIncognito) ...[
              const SizedBox(height: 18),
              Text(
                isEn
                    ? 'Incognito chats are not saved to history.'
                    : 'Los chats de incógnito no se guardan en el historial.',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13.5, color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Regla 5 & 9: Widget supremo de esfera donde cada punto cambia de tamaño aleatoriamente
class _InterlockingComposerArea extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onModelTap;
  const _InterlockingComposerArea({
    required this.controller,
    required this.onSend,
    required this.onModelTap,
  });

  @override
  State<_InterlockingComposerArea> createState() => _InterlockingComposerAreaState();
}

class _InterlockingComposerAreaState extends State<_InterlockingComposerArea> with SingleTickerProviderStateMixin {
  late AnimationController _auraController;
  bool _hasAttachment = false;
  bool _isRecording = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechEnabled = false;
  bool _speechInitialized = false; // lazy: solo true después del primer tap

  @override
  void initState() {
    super.initState();
    _auraController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();
    // NO inicializamos el speech aquí. Se inicializa solo cuando el usuario toca el mic.
  }

  Future<void> _ensureSpeechInitialized() async {
    if (_speechInitialized) return;
    try {
      _speechEnabled = await _speech.initialize();
      _speechInitialized = true;
    } catch (_) {
      _speechEnabled = false;
    }
  }

  void _showAttachmentMenu() {
    HapticFeedback.vibrate();
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isEn = _isDeviceEnglish(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: isLight ? const Color(0xFFFAF8F5) : const Color(0xFF1A1612),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: ExodoColors.amber),
                title: Text(isEn ? 'Camera' : 'Cámara', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: isLight ? Colors.black87 : Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picker = ImagePicker();
                  final XFile? photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
                  if (photo != null) {
                    setState(() => _hasAttachment = true);
                    widget.controller.text += '[Foto: ${photo.name}] ';
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: ExodoColors.amber),
                title: Text(isEn ? 'Gallery' : 'Galería', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: isLight ? Colors.black87 : Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picker = ImagePicker();
                  final XFile? media = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
                  if (media != null) {
                    setState(() => _hasAttachment = true);
                    widget.controller.text += '[Galería: ${media.name}] ';
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_rounded, color: ExodoColors.amber),
                title: Text(isEn ? 'Files' : 'Archivos', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: isLight ? Colors.black87 : Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final res = await FilePicker.platform.pickFiles(allowMultiple: true);
                  if (res != null && res.files.isNotEmpty) {
                    setState(() => _hasAttachment = true);
                    final names = res.files.map((e) => e.name).join(', ');
                    widget.controller.text += '[Archivos: $names] ';
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _auraController.dispose();
    super.dispose();
  }

  // [D3] Mapear código de locale de la app a locale BCP-47 que speech_to_text
  // reconozca en Android. Cuando el dispositivo no tiene el locale instalado,
  // el plugin cae al default del sistema (que puede ser 'en' en la mayoría).
  String _sttLocaleFor(String appLocale) {
    switch (appLocale) {
      case 'es':
        return 'es-DO';          // Dominican Spanish (preserva acento local)
      case 'en':
        return 'en-US';
      case 'fr':
        return 'fr-FR';
      case 'pt':
        return 'pt-BR';
      case 'it':
        return 'it-IT';
      case 'de':
        return 'de-DE';
      default:
        return 'en-US';
    }
  }

  String _getPlaceholder(BuildContext context) {
    if (_isDeviceEnglish(context)) return 'Reply to Exodo...';
    return 'Hablar con Exodo...';
  }

  Widget _buildOfflineInsideCapsule(BuildContext context, AppState state, bool isEn, bool isLight) {
    final softBlack = const Color(0xFF2A2622); // negro suave para textos en light mode
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 20, color: ExodoColors.amber),
              const SizedBox(width: 8),
              Text(
                isEn ? "You're offline" : "Estás desconectado",
                style: GoogleFonts.syne(fontSize: 16, fontWeight: FontWeight.bold, color: isLight ? softBlack : ExodoColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (isEn)
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.inter(fontSize: 13, color: isLight ? softBlack : ExodoColors.textSecondary, height: 1.4),
                children: [
                  const TextSpan(text: "To continue sending messages, "),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.vibrate();
                        // [D2] Try/catch + mounted guard: si está OFFLINE, signOut
                        // puede tirar timeout o excepción. Aseguramos que aunque
                        // falle, el _RootSwitcher detecte currentUser == null y
                        // muestre AuthScreen. Sin esto, el usuario se queda
                        // "atascado" en el estado bloqueado.
                        try {
                          await SupabaseService.signOut().timeout(
                            const Duration(seconds: 3),
                            onTimeout: () {},
                          );
                        } catch (_) {
                          // offline o error de red: ignorar y dejar que el
                          // _RootSwitcher redibuje con currentUser == null
                        }
                      },
                      child: Text(
                        "upgrade",
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: ExodoColors.amber, decoration: TextDecoration.underline, decorationColor: ExodoColors.amber),
                      ),
                    ),
                  ),
                  const TextSpan(text: " your plan to Pro or "),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.vibrate();
                        // [D2] Idem: signOut con timeout corto + try/catch.
                        try {
                          await SupabaseService.signOut().timeout(
                            const Duration(seconds: 3),
                            onTimeout: () {},
                          );
                        } catch (_) {}
                      },
                      child: Text(
                        "sign in",
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: ExodoColors.amber, decoration: TextDecoration.underline, decorationColor: ExodoColors.amber),
                      ),
                    ),
                  ),
                  const TextSpan(text: "."),
                ],
              ),
            )
          else
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.inter(fontSize: 13, color: isLight ? softBlack : ExodoColors.textSecondary, height: 1.4),
                children: [
                  const TextSpan(text: "Para seguir enviando mensajes, "),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.vibrate();
                        // [D2] signOut resiliente offline-safe.
                        try {
                          await SupabaseService.signOut().timeout(
                            const Duration(seconds: 3),
                            onTimeout: () {},
                          );
                        } catch (_) {}
                      },
                      child: Text(
                        "actualice",
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: ExodoColors.amber, decoration: TextDecoration.underline, decorationColor: ExodoColors.amber),
                      ),
                    ),
                  ),
                  const TextSpan(text: " su plan a Pro o "),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.vibrate();
                        // [D2] signOut resiliente offline-safe.
                        try {
                          await SupabaseService.signOut().timeout(
                            const Duration(seconds: 3),
                            onTimeout: () {},
                          );
                        } catch (_) {}
                      },
                      child: Text(
                        "inicie sesión",
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: ExodoColors.amber, decoration: TextDecoration.underline, decorationColor: ExodoColors.amber),
                      ),
                    ),
                  ),
                  const TextSpan(text: "."),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode && !state.isIncognito;
    final isEn = _isDeviceEnglish(context);

    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Regla 7 & Recreación limpia: Tab 2 nativo con preservación de espacio geométrica
          Visibility(
            visible: state.showTab2Banner && !state.isIncognito && !state.isPro,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.86,
              padding: const EdgeInsets.fromLTRB(16, 8, 14, 22),
              decoration: BoxDecoration(
                color: isLight ? const Color(0xFF131313) : const Color(0xFFEFECE4),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: isLight ? Border.all(color: const Color(0xFF131313), width: 1.0) : Border.all(color: Colors.transparent, width: 1.0),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isDeviceEnglish(context) ? 'More capacity with XPi PRO' : 'Mas capacidad con XPi PRO',
                      style: GoogleFonts.jetBrainsMono(
                        color: isLight ? const Color(0xFFF5F2EB) : const Color(0xFF55514C),
                        fontSize: 12.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _UpgradeModal.show(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Text(
                          _isDeviceEnglish(context) ? 'Upgrade' : 'Actualizar',
                          style: GoogleFonts.jetBrainsMono(
                            color: ExodoColors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => state.dismissTab2Banner(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Icon(Icons.close, size: 16, color: isLight ? Colors.white70 : Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Regla 10 & 13 Validados: Tab 1 entrelazado con traslación constante e inmutable
          Transform.translate(
            offset: const Offset(0, -14),
            child: Container(
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFFE5DECF) : ExodoColors.composerBg,
              borderRadius: BorderRadius.circular(32),
              border: isLight ? Border.all(color: const Color(0xFFD4CEBF), width: 1.0) : Border.all(color: Colors.transparent, width: 1.0),
            ),
            padding: state.guestIsBlocked 
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
                : const EdgeInsets.fromLTRB(20, 8, 18, 8),
            child: state.guestIsBlocked
                ? _buildOfflineInsideCapsule(context, state, isEn, isLight)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: widget.controller,
                        maxLines: 4,
                        minLines: 1,
                        onSubmitted: (_) => widget.onSend(),
                        style: TextStyle(fontSize: 16, color: isLight ? const Color(0xFF171615) : Colors.white),
                        decoration: InputDecoration(
                          hintText: _getPlaceholder(context),
                          hintStyle: GoogleFonts.inter(color: const Color(0xFF7B7872), fontSize: 16),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Compartimento Izquierdo expandido para absorber cambios de texto/tamaño
                          Expanded(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Botón +
                                InkWell(
                                  onTap: _showAttachmentMenu,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(color: isLight ? const Color(0xFFFBF9F5) : const Color(0xFF131313), shape: BoxShape.circle),
                                    child: Icon(Icons.add, size: 20, color: isLight ? const Color(0xFF171615) : Colors.white70),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Selector de modelo
                                Flexible(
                                  child: GestureDetector(
                                    onTap: widget.onModelTap,
                                    child: AnimatedBuilder(
                                      animation: _auraController,
                                      builder: (context, _) {
                                        final isXpiPro = state.isPro && (state.selectedModel.id == 'ehyeh' || state.selectedModel.title == 'XPi');
                                        final t = _auraController.value;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isLight ? const Color(0xFFFBF9F5) : const Color(0xFF131313),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: isXpiPro
                                                  ? ExodoColors.amber.withValues(alpha: 0.40 + 0.60 * ((math.sin(t * math.pi * 2) + 1) / 2))
                                                  : Colors.transparent,
                                              width: 1.0,
                                            ),
                                            boxShadow: isXpiPro
                                                ? [
                                                    BoxShadow(
                                                      color: ExodoColors.amber.withValues(alpha: 0.15 + 0.25 * ((math.sin(t * math.pi * 2) + 1) / 2)),
                                                      blurRadius: 10,
                                                      spreadRadius: 1,
                                                      offset: Offset(6 * math.cos(t * math.pi * 2), 3 * math.sin(t * math.pi * 2)),
                                                    ),
                                                    BoxShadow(
                                                      color: ExodoColors.amber.withValues(alpha: 0.10 + 0.18 * ((math.cos(t * math.pi * 2 * 1.3) + 1) / 2)),
                                                      blurRadius: 14,
                                                      spreadRadius: 0,
                                                      offset: Offset(-5 * math.sin(t * math.pi * 2), -3 * math.cos(t * math.pi * 2)),
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  state.selectedModel.title,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.jetBrainsMono(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: isLight ? const Color(0xFF171615) : Colors.white,
                                                  ),
                                                ),
                                              ),
                                              if (state.selectedModel.plan == 'hazak') ...[
                                                const SizedBox(width: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: isLight ? const Color(0xFFE5DECF) : const Color(0xFF3A352F),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: isLight ? Colors.black12 : Colors.white24),
                                                  ),
                                                  child: Text(
                                                    'PRO',
                                                    style: GoogleFonts.jetBrainsMono(
                                                      fontSize: 9.0,
                                                      fontWeight: FontWeight.bold,
                                                      color: isLight ? const Color(0xFF171615) : Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(width: 4),
                                              Icon(Icons.keyboard_arrow_down, size: 16, color: isLight ? const Color(0xFF171615) : Colors.white70),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Botón Mic y Botón Dinámico (Live Chat / Send)
                          AnimatedBuilder(
                            animation: widget.controller,
                            builder: (context, _) {
                              final hasText = widget.controller.text.trim().isNotEmpty;
                              final shouldShowSend = hasText || _hasAttachment || _isRecording;

                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Micrófono absolutamente fijo sin animación ni desplazamiento
                                  IconButton(
                                    icon: Icon(
                                      _isRecording ? Icons.mic : Icons.mic_none,
                                      color: _isRecording
                                          ? ExodoColors.error
                                          : (shouldShowSend
                                              ? (isLight ? Colors.black54 : ExodoColors.textSecondary)
                                              : (isLight ? Colors.black87 : Colors.white70)),
                                    ),
                                    onPressed: () async {
                                      HapticFeedback.vibrate();
                                      if (!_isRecording) {
                                        // [D3] Capturamos locale, mensaje y messenger ANTES del await
                                        // para evitar usar `context` después de una espera.
                                        final sttLocaleId = _sttLocaleFor(AppI18n.of(context).localeCode);
                                        final micPermissionMsg = AppI18n.of(context).t('mic.permission_required');
                                        final messenger = ScaffoldMessenger.of(context);
                                        // Inicialización lazy: solo pedimos permisos cuando el usuario toca el mic.
                                        await _ensureSpeechInitialized();
                                        if (!mounted) return; // Parche Fase 1: evita usar context si el widget se desmontó
                                        if (_speechEnabled) {
                                          setState(() => _isRecording = true);
                                          await _speech.listen(
                                            onResult: (result) {
                                              widget.controller.text = result.recognizedWords;
                                            },
                                            listenOptions: stt.SpeechListenOptions(
                                              partialResults: true,
                                              localeId: sttLocaleId,
                                              cancelOnError: true,
                                            ),
                                          );
                                        } else {
                                          messenger.showSnackBar(
                                            SnackBar(content: Text(micPermissionMsg)),
                                          );
                                        }
                                      } else {
                                        setState(() => _isRecording = false);
                                        await _speech.stop();
                                      }
                                    },
                                  ),

                                  // Botón dinámico: Chat en Vivo fijo <-> Botón de enviar / detener
                                  GestureDetector(
                                    onTap: () {
                                      if (state.isGenerating) {
                                        HapticFeedback.mediumImpact();
                                        state.stopGeneration();
                                      } else if (shouldShowSend) {
                                        setState(() {
                                          _hasAttachment = false;
                                          _isRecording = false;
                                        });
                                        widget.onSend();
                                      } else {
                                        // [D1] Live chat no implementado todavía: feedback visual
                                        // honesto para que el usuario sepa que NO es un botón roto.
                                        HapticFeedback.lightImpact();
                                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            duration: const Duration(seconds: 2),
                                            content: Row(
                                              children: [
                                                const Icon(Icons.bolt_outlined, color: ExodoColors.amber, size: 18),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    AppI18n.of(context).t('live.coming_soon'),
                                                    style: const TextStyle(color: Colors.white),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      margin: const EdgeInsets.only(left: 2, right: 2),
                                      decoration: BoxDecoration(
                                        color: (state.isGenerating || shouldShowSend)
                                            ? (isLight ? const Color(0xFF131313) : const Color(0xFFFBF9F5))
                                            : const Color(0xFF131313),
                                        shape: BoxShape.circle,
                                        border: (state.isGenerating || shouldShowSend) ? null : Border.all(color: ExodoColors.amber.withValues(alpha: 0.5), width: 1.2),
                                      ),
                                      child: Icon(
                                        state.isGenerating
                                            ? Icons.stop_rounded
                                            : (shouldShowSend ? Icons.arrow_upward : Icons.graphic_eq_rounded),
                                        size: state.isGenerating ? 22 : 19,
                                        color: (state.isGenerating || shouldShowSend)
                                            ? (isLight ? Colors.white : const Color(0xFF141210))
                                            : ExodoColors.amber,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
            ),
          ),
        ],
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
    final trackColor = isLight ? const Color(0xFFD4CCBC) : const Color(0xFF131313);
    final fillColor = isLight ? const Color(0xFF171615) : ExodoColors.textPrimary;
    final textColor = isLight ? const Color(0xFF171615) : ExodoColors.textPrimary;
    final subTextColor = isLight ? const Color(0xFF7B7872) : ExodoColors.textSecondary;

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
                  _statItem('CONSUMIDO', '${widget.used} ($pct%)', textColor),
                  
                  // En PRO acomodamos simétricamente DISPONIBLE en el centro
                  if (widget.isPro)
                    _statItem('DISPONIBLE', '$remaining', textColor),

                  _statItem('REINICIO EN', _getCountdown(), ExodoColors.amber),

                  // En FREE colocamos MÁS CAPACIDAD a la derecha
                  if (!widget.isPro)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.vibrate();
                        _UpgradeModal.show(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: ExodoColors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: ExodoColors.amber.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded, size: 12, color: ExodoColors.amber),
                            const SizedBox(width: 3),
                            Text(
                              'MÁS CAPACIDAD',
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
class _ThinkingBubble extends StatelessWidget {
  final Animation<double> pulseAnim;
  const _ThinkingBubble({required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode && !state.isIncognito;
    final logoColor = isLight ? ExodoColors.background : ExodoColors.amber;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: AnimatedBuilder(
          animation: pulseAnim,
          builder: (context, _) {
            final v = pulseAnim.value;
            return Opacity(
              opacity: 0.4 + (v * 0.6).clamp(0.0, 0.6),
              child: Image.asset(
                'assets/images/exodo_arrow_logo.png',
                width: 28,
                height: 28,
                color: logoColor,
              ),
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

  void _showEditDialog(BuildContext context) {
    final ctrl = TextEditingController(text: message.content);
    final isLight = Theme.of(context).brightness == Brightness.light;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isLight ? const Color(0xFFF5F2EB) : const Color(0xFF1E1C19),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _isDeviceEnglish(context) ? 'Edit message' : 'Editar mensaje',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
          ),
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          minLines: 2,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
          ),
          decoration: InputDecoration(
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
              _isDeviceEnglish(context) ? 'Cancel' : 'Cancelar',
              style: GoogleFonts.inter(color: ExodoColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              final newText = ctrl.text.trim();
              if (newText.isNotEmpty) {
                context.read<AppState>().updateUserMessage(message.id, newText);
              }
              Navigator.pop(ctx);
            },
            child: Text(
              _isDeviceEnglish(context) ? 'Save' : 'Guardar',
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
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isLight ? const Color(0xFFE5DECF) : const Color(0xFF131313),
                borderRadius: BorderRadius.circular(20),
                border: isLight ? Border.all(color: const Color(0xFFD4CEBF), width: 1.0) : null,
              ),
              child: MarkdownBody(
                data: message.content,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: GoogleFonts.inter(fontSize: 15, color: isLight ? const Color(0xFF171615) : Colors.white),
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
                  tooltip: _isDeviceEnglish(context) ? 'Copy' : 'Copiar',
                  color: isLight ? Colors.black38 : Colors.white38,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Clipboard.setData(ClipboardData(text: message.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _isDeviceEnglish(context) ? 'Copied' : 'Copiado',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.edit_rounded,
                  tooltip: _isDeviceEnglish(context) ? 'Edit' : 'Editar',
                  color: isLight ? Colors.black38 : Colors.white38,
                  onTap: () => _showEditDialog(context),
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
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: GoogleFonts.inter(
                fontSize: 15.5,
                color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
                height: 1.45,
              ),
              code: GoogleFonts.jetBrainsMono(
                backgroundColor: isLight ? const Color(0xFFEFECE4) : ExodoColors.surface,
                color: isLight ? const Color(0xFFB85A35) : ExodoColors.amber,
              ),
              codeblockDecoration: BoxDecoration(
                color: isLight ? const Color(0xFFF2ECE1) : ExodoColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ExodoColors.border),
              ),
            ),
          ),
          if (message.intentDetected != null) ...[
            const SizedBox(height: 8),
            Text(_isDeviceEnglish(context) ? 'Intent: ${message.intentDetected}' : 'Intención: ${message.intentDetected}', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: ExodoColors.amber.withValues(alpha: 0.8))),
          ],
          if (message.sources.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SourcesSheet(sources: message.sources),
          ],
          const SizedBox(height: 10),
          _MessageActionBar(message: message),
          const SizedBox(height: 14),
          Opacity(
            opacity: 0.5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _isDeviceEnglish(context)
                        ? 'Exodo is AI and can make mistakes. Please double-check responses.'
                        : 'Exodo es IA y puede cometer errores. Por favor verifica las respuestas.',
                    textAlign: TextAlign.end,
                    style: GoogleFonts.inter(fontSize: 11, height: 1.35, color: isLight ? Colors.black : Colors.white),
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
    final label = _isDeviceEnglish(context) ? 'Sources' : 'Fuentes';

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
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isDeviceEnglish(context) ? 'Consulted Sources' : 'Fuentes Consultadas',
                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: isLight ? Colors.black : Colors.white),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sources.length,
                      separatorBuilder: (_, _) => const Divider(height: 16, color: Colors.white12),
                      itemBuilder: (ctx, idx) {
                        final s = sources[idx];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: circleColors[idx % circleColors.length],
                            child: Text(_sourceInitials(s), style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                          title: Text(s.title.isNotEmpty ? s.title : s.url, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: isLight ? Colors.black87 : Colors.white)),
                          subtitle: s.url.isNotEmpty ? Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: ExodoColors.amber)) : null,
                          onTap: s.url.isNotEmpty ? () {
                            HapticFeedback.lightImpact();
                            Clipboard.setData(ClipboardData(text: s.url));
                            Navigator.pop(ctx);
                          } : null,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isLight ? const Color(0xFFEFECE4) : const Color(0xFF1E1C19),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: isLight ? Colors.black12 : Colors.white24, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (ctx) {
                final displaySources = sources.take(4).toList();
                return SizedBox(
                  height: 24,
                  width: (displaySources.length * 16.0) + 8.0,
                  child: Stack(
                    children: [
                      for (int i = 0; i < displaySources.length; i++)
                        Positioned(
                          left: i * 16.0,
                          child: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: circleColors[i % circleColors.length],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isLight ? const Color(0xFFEFECE4) : const Color(0xFF1E1C19),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              _sourceInitials(displaySources[i]),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
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
  return t.length >= 2 ? t.substring(0, 2).toUpperCase() : t.substring(0, 1).toUpperCase();
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
      Clipboard.setData(ClipboardData(text: message.content));
    }

    void like() {
      HapticFeedback.mediumImpact();
    }

    void dislike() {
      HapticFeedback.mediumImpact();
    }

    return Wrap(
      spacing: 18,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ActionButton(assetPath: 'assets/images/copy-2-svgrepo-com.png', tooltip: _isDeviceEnglish(context) ? 'Copy' : 'Copiar', color: subText, onTap: copy),
        _ActionButton(assetPath: 'assets/images/like-1-svgrepo-com.png', tooltip: _isDeviceEnglish(context) ? 'Like' : 'Me gusta', color: subText, onTap: like),
        _ActionButton(assetPath: 'assets/images/like-1-svgrepo-com.png', flipVertically: true, tooltip: _isDeviceEnglish(context) ? 'Dislike' : 'No me gusta', color: subText, onTap: dislike),
        _ActionButton(assetPath: 'assets/images/share-svgrepo-com.png', tooltip: _isDeviceEnglish(context) ? 'Share' : 'Compartir', color: subText, onTap: share),
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
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: childWidget,
        ),
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
    final isEn = _isDeviceEnglish(context);

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
              decoration: BoxDecoration(color: isLight ? Colors.black26 : ExodoColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          ...exodoModels.map((m) {
            final active = state.selectedModel.id == m.id;
            final isProModel = m.plan == 'hazak';
            final isFree = state.profile?.plan != 'hazak';

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
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
                  Text(m.title, style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold, fontSize: 15, color: active ? ExodoColors.amber : (isLight ? const Color(0xFF171615) : Colors.white))),
                  Text(m.subtitle, style: GoogleFonts.jetBrainsMono(fontSize: 13, color: active ? ExodoColors.amber : (isLight ? Colors.black54 : Colors.white70))),
                  if (isProModel)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: active ? ExodoColors.amber.withValues(alpha: 0.18) : (isLight ? const Color(0xFFEFECE4) : const Color(0xFF3A352F)),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: active ? ExodoColors.amber : (isLight ? Colors.black12 : Colors.white24)),
                      ),
                      child: Text(
                        'PRO',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: active ? ExodoColors.amber : (isLight ? const Color(0xFF33302C) : Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Text(isEn ? m.descriptionEn : m.description, style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: active ? ExodoColors.amber : (isLight ? Colors.black54 : Colors.white70))),
              trailing: active ? const Icon(Icons.check, size: 18, color: ExodoColors.amber) : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              tileColor: Colors.transparent,
            );
          }),
          const SizedBox(height: 16),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_rounded, size: 15, color: ExodoColors.amber.withValues(alpha: 0.8)),
                const SizedBox(width: 6),
                Text(
                  isEn ? 'thinking mode enabled by default' : 'modo thinking activado por defecto',
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: isLight ? Colors.black54 : ExodoColors.textSecondary),
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

class _PulsingXpiAuraState extends State<_PulsingXpiAura> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
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
            boxShadow: [BoxShadow(color: ExodoColors.amber.withValues(alpha: op), blurRadius: blur, spreadRadius: 1)],
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141210),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(ctx),
                ),
                Center(
                  child: Column(
                    children: [
                      Text('Get more Exodo', style: GoogleFonts.syne(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 6),
                      Text('Choose the plan right for you', style: GoogleFonts.inter(fontSize: 14, color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF221F1C),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF38332E)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pro', style: GoogleFonts.syne(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('For everyday productivity', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => isAnnual = false),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: !isAnnual ? const Color(0xFF2E2A25) : const Color(0xFF1E1C19),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: !isAnnual ? ExodoColors.amber : const Color(0xFF332F2A), width: !isAnnual ? 1.5 : 1),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(!isAnnual ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: !isAnnual ? ExodoColors.amber : Colors.white38),
                                    const SizedBox(height: 10),
                                    Text('\$4.99', style: GoogleFonts.jetBrainsMono(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                    Text('Billed monthly', style: GoogleFonts.inter(fontSize: 11, color: Colors.white60)),
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
                                  color: isAnnual ? const Color(0xFF2E2A25) : const Color(0xFF1E1C19),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: isAnnual ? ExodoColors.amber : const Color(0xFF332F2A), width: isAnnual ? 1.5 : 1),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Icon(isAnnual ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: isAnnual ? ExodoColors.amber : Colors.white38),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: ExodoColors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                                          child: Text('Save 16.5%', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: ExodoColors.amber)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text('\$49.99', style: GoogleFonts.jetBrainsMono(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                    Text('Billed annually', style: GoogleFonts.inter(fontSize: 11, color: Colors.white60)),
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
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            context.read<AppState>().upgradeToProPlan();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_isDeviceEnglish(context) ? '🎉 XPi PRO activated for this session!' : '🎉 ¡Plan XPi PRO activado con éxito!'),
                                backgroundColor: ExodoColors.amber,
                              ),
                            );
                          },
                          child: Text('Get Pro plan', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('Everything in Free, plus:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 8),
                      _item('Everything in Free'),
                      _item('Razonamiento avanzado ilimitado XPi'),
                      _item('Acceso prioritario a Nemotron 3 Ultra'),
                      _item('Proyectos y memorias ilimitadas'),
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

  static Widget _item(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check, size: 15, color: Colors.white70),
          const SizedBox(width: 8),
          Text(text, style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white70)),
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
  const _ScrollToBottomHost({required this.controller, required this.messagesCount});

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
