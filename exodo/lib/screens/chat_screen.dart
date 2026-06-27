import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/supabase_service.dart';
import '../widgets/drawer_menu.dart';
import '../theme/exodo_theme.dart';

bool _isDeviceEnglish(BuildContext context) {
  try {
    final sys = ui.PlatformDispatcher.instance.locale.languageCode;
    if (sys == 'en') return true;
  } catch (_) {}
  return Localizations.localeOf(context).languageCode == 'en';
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

  @override
  void initState() {
    super.initState();
    _thinkingAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _ambientBgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat(reverse: true);
    // Regla 5 & 9: Pulso continuo para cambio de tamaño de puntos aleatorio
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);

  }

  void _checkAndShowFocusModal() {
    // Extirpado por completo. Cero modales de preguntas.
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _ModelSelectorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode && !state.isIncognito;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    _scrollToBottom();

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
              // Stage principal o vista Offline de bloqueo Guest
              Expanded(
                child: state.guestIsBlocked
                    ? const _GuestOfflineStage()
                    : state.currentMessages.isEmpty
                        ? _OriginalDesignStage(
                            pulseAnim: _pulseCtrl,
                            fullName: state.profile?.fullName,
                          )
                        : ListView.builder(
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
              ),

              // Ocultar barra inferior si está bloqueado ("sin botones y sin nada")
              if (!state.guestIsBlocked)
                _InterlockingComposerArea(
                  controller: _inputCtrl,
                  onSend: () {
                    final text = _inputCtrl.text;
                    if (text.trim().isEmpty) return;
                    if (state.tokensUsed >= state.tokensLimit && state.profile?.plan != 'hazak') {
                      HapticFeedback.vibrate();
                      _UpgradeModal.show(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_isDeviceEnglish(context) ? '⚠️ Daily limit reached. Activate Hazak Pro to continue.' : '⚠️ Alcanzaste tu capacidad diaria. Activa Hazak Pro para continuar.'),
                          backgroundColor: const Color(0xFFC9933A),
                        ),
                      );
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

// Regla 2 & 7: Fondo ambiental orgánico no lineal con focos fluctuantes en Modo Dark
class _AnimatedAmbientBackground extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _AnimatedAmbientBackground({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    
    // Regla de validación: Desactivado en Modo Claro o Modo Incógnito
    if (state.isIncognito || !state.isDarkMode) {
      return Container(
        color: (state.isDarkMode || state.isIncognito) ? ExodoColors.background : const Color(0xFFFBF9F5),
        child: child,
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _AmbientGlowPainter(animation.value),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _AmbientGlowPainter extends CustomPainter {
  final double t;
  _AmbientGlowPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(ExodoColors.background, BlendMode.src);

    // Animación fluida estilo Gemini App anclada abajo con la paleta oficial de Exodo (Ámbar, Polvo, Crema, Blanco)
    final orbs = [
      _GlowOrb(ExodoColors.amber.withOpacity(0.15), 0.28, 0.80, size.width * 0.76, 0.45, 0.35, 0.0),
      _GlowOrb(ExodoColors.textSecondary.withOpacity(0.12), 0.78, 0.76, size.width * 0.80, 0.35, 0.45, 1.7),
      _GlowOrb(ExodoColors.textPrimary.withOpacity(0.09), 0.55, 0.86, size.width * 0.72, 0.50, 0.30, 3.2),
      _GlowOrb(Colors.white.withOpacity(0.06), 0.40, 0.74, size.width * 0.65, 0.40, 0.50, 4.5),
    ];

    for (final orb in orbs) {
      final offsetX = math.sin(t * math.pi * 2 * orb.speedX + orb.phase) * (size.width * 0.22);
      final offsetY = math.cos(t * math.pi * 2 * orb.speedY + orb.phase) * (size.height * 0.06);
      final center = Offset(size.width * orb.baseX + offsetX, size.height * orb.baseY + offsetY);
      
      final currentRadius = orb.radius * (0.88 + 0.16 * math.sin(t * math.pi * 2 + orb.phase));

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [orb.color, orb.color.withOpacity(0.0)],
        ).createShader(Rect.fromCircle(center: center, radius: currentRadius));

      canvas.drawCircle(center, currentRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_AmbientGlowPainter old) => old.t != t;
}

class _GlowOrb {
  final Color color;
  final double baseX, baseY, radius, speedX, speedY, phase;
  const _GlowOrb(this.color, this.baseX, this.baseY, this.radius, this.speedX, this.speedY, this.phase);
}

class _OriginalDesignStage extends StatelessWidget {
  final Animation<double> pulseAnim;
  final String? fullName;
  const _OriginalDesignStage({required this.pulseAnim, required this.fullName});

  String _getGreeting(BuildContext context, AppState state) {
    final firstName = (fullName != null && fullName!.trim().isNotEmpty)
        ? fullName!.trim().split(' ').first
        : 'BRAZOBAN';
    final isEn = _isDeviceEnglish(context);
    final temp = state.currentTempC;

    if (temp != null) {
      if (temp <= 21.0) {
        return isEn ? 'Cold & Exodo, better than coffee?, $firstName.' : 'Frío y Exodo, ¿mejor que un café?, $firstName.';
      } else if (temp >= 31.0) {
        return isEn ? 'Grab something cold, really hot, $firstName.' : 'Toma algo frío, hace mucho calor, $firstName.';
      }
    }

    final hour = DateTime.now().hour;
    if (isEn) {
      if (hour >= 0 && hour < 6) return 'Late night hustle, $firstName.';
      if (hour < 12) return 'Morning, $firstName.';
      if (hour < 18) return 'Afternoon, $firstName.';
      return 'Night, $firstName.';
    } else {
      if (hour >= 0 && hour < 6) return 'Ni la madrugada te detiene, $firstName.';
      if (hour < 12) return 'Cafecito con Exodo, $firstName.';
      if (hour < 18) return 'Tarde productiva, $firstName.';
      return 'La noche es joven, $firstName.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = Theme.of(context).brightness == Brightness.light && !state.isIncognito;
    final isEn = _isDeviceEnglish(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: state.isIncognito
              ? [
                  _AnimatedIncognitoHat(
                    isIncognito: state.isIncognito,
                    child: Image.asset(
                      'assets/images/incognito-svgrepo-com.png',
                      width: 76,
                      height: 76,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    isEn
                        ? 'Incognito chats are not saved to history.'
                        : 'Los chats de incógnito no se guardan en el historial.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      color: Colors.white70,
                    ),
                  ),
                ]
              : [
                  Text(
                    _getGreeting(context, state),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isLight ? const Color(0xFF171615) : Colors.white,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Exodo by Behavior',
                    style: GoogleFonts.syne(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: isLight ? const Color(0xFF66605A) : const Color(0xFFE5DECF),
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}

// Regla 5 & 9: Widget supremo de esfera donde cada punto cambia de tamaño aleatoriamente
class _RandomScalingDotSphere extends StatelessWidget {
  final Animation<double> animation;
  final double size;
  const _RandomScalingDotSphere({required this.animation, this.size = 76});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _DotSpherePainter(animation.value)),
      ),
    );
  }
}

class _DotSpherePainter extends CustomPainter {
  final double t;
  _DotSpherePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ExodoColors.amber;
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    const dots = [
      _DotDef(0.0, 0.0, 1.3, 0.0),
      _DotDef(0.36, 0.0, 1.1, 1.4),
      _DotDef(-0.36, 0.0, 1.4, 2.7),
      _DotDef(0.0, 0.36, 0.9, 0.8),
      _DotDef(0.0, -0.36, 1.2, 3.5),
      _DotDef(0.26, 0.26, 1.0, 1.9),
      _DotDef(-0.26, 0.26, 1.3, 4.4),
      _DotDef(0.26, -0.26, 1.1, 0.6),
      _DotDef(-0.26, -0.26, 0.9, 3.1),
      _DotDef(0.66, 0.0, 0.8, 3.8),
      _DotDef(-0.66, 0.0, 1.0, 1.2),
      _DotDef(0.0, 0.66, 0.7, 5.0),
      _DotDef(0.0, -0.66, 0.9, 2.3),
      _DotDef(0.48, 0.48, 0.8, 0.4),
      _DotDef(-0.48, 0.48, 0.9, 1.8),
      _DotDef(0.48, -0.48, 0.7, 4.1),
      _DotDef(-0.48, -0.48, 0.8, 5.3),
    ];

    for (final d in dots) {
      final pos = center + Offset(d.x * r * 0.82, d.y * r * 0.82);
      final scale = 0.40 + 0.60 * ((math.sin(t * math.pi * 2 * d.speed + d.phase) + 1) / 2);
      canvas.drawCircle(pos, size.width * 0.068 * scale, paint);
    }
  }

  @override
  bool shouldRepaint(_DotSpherePainter old) => old.t != t;
}

class _DotDef {
  final double x, y, speed, phase;
  const _DotDef(this.x, this.y, this.speed, this.phase);
}

// Estructura entrelazada Tab 1 y Tab 2
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

  @override
  void initState() {
    super.initState();
    _auraController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speech.initialize();
    } catch (_) {}
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
              Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
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

  String _getPlaceholder(BuildContext context) {
    if (_isDeviceEnglish(context)) return 'Reply to Exodo...';
    return 'Hablar con Exodo...';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode && !state.isIncognito;

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
                color: isLight ? const Color(0xFF161412) : const Color(0xFFEFECE4),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(color: isLight ? const Color(0xFF2A241D) : const Color(0xFFDCD5C5)),
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
              color: isLight ? const Color(0xFFE5DECF) : const Color(0xFF161412),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: isLight ? const Color(0xFFD4CEBF) : ExodoColors.border),
            ),
            padding: const EdgeInsets.fromLTRB(20, 8, 18, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: widget.controller,
                  maxLines: 4,
                  minLines: 1,
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
                              decoration: BoxDecoration(color: isLight ? const Color(0xFFFBF9F5) : const Color(0xFF25211D), shape: BoxShape.circle),
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
                                      color: isLight ? const Color(0xFFFBF9F5) : const Color(0xFF25211D),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isXpiPro
                                            ? ExodoColors.amber.withOpacity(0.40 + 0.60 * ((math.sin(t * math.pi * 2) + 1) / 2))
                                            : Colors.transparent,
                                        width: 1.0,
                                      ),
                                      boxShadow: isXpiPro
                                          ? [
                                              BoxShadow(
                                                color: ExodoColors.amber.withOpacity(0.15 + 0.25 * ((math.sin(t * math.pi * 2) + 1) / 2)),
                                                blurRadius: 10,
                                                spreadRadius: 1,
                                                offset: Offset(6 * math.cos(t * math.pi * 2), 3 * math.sin(t * math.pi * 2)),
                                              ),
                                              BoxShadow(
                                                color: ExodoColors.amber.withOpacity(0.10 + 0.18 * ((math.cos(t * math.pi * 2 * 1.3) + 1) / 2)),
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
                                  if (_speechEnabled) {
                                    setState(() => _isRecording = true);
                                    await _speech.listen(
                                      onResult: (result) {
                                        widget.controller.text = result.recognizedWords;
                                      },
                                      localeId: 'es_DO',
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(_isDeviceEnglish(context) ? '⚠️ Microphone permission required for voice dictation' : '⚠️ Permiso de micrófono requerido para dictado de voz')),
                                    );
                                  }
                                } else {
                                  setState(() => _isRecording = false);
                                  await _speech.stop();
                                }
                              },
                            ),

                            // Botón dinámico: Chat en Vivo fijo <-> Botón de enviar
                            GestureDetector(
                              onTap: () {
                                if (shouldShowSend) {
                                  setState(() {
                                    _hasAttachment = false;
                                    _isRecording = false;
                                  });
                                  widget.onSend();
                                } else {
                                  // Botón chat en vivo desactivado por ahora, no hace nada
                                }
                              },
                              child: Container(
                                width: 38,
                                height: 38,
                                margin: const EdgeInsets.only(left: 2, right: 2),
                                decoration: BoxDecoration(
                                  color: shouldShowSend
                                      ? (isLight ? const Color(0xFF161412) : const Color(0xFFFBF9F5))
                                      : (isLight ? const Color(0xFF2A241D) : const Color(0xFF25211D)),
                                  shape: BoxShape.circle,
                                  border: shouldShowSend ? null : Border.all(color: ExodoColors.amber.withOpacity(0.5), width: 1.2),
                                ),
                                child: Icon(
                                  shouldShowSend ? Icons.arrow_upward : Icons.graphic_eq_rounded,
                                  size: 19,
                                  color: shouldShowSend
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

    final bgColor = isLight ? const Color(0xFFE5DECF) : ExodoColors.surface;
    final borderColor = isLight ? const Color(0xFFD4CCBC) : ExodoColors.border;
    final trackColor = isLight ? const Color(0xFFD4CCBC) : const Color(0xFF2A241D);
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
          border: Border.all(
            color: _isExpanded ? ExodoColors.amber.withOpacity(0.5) : borderColor,
            width: 1,
          ),
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

                  // En FREE colocamos MÁS CAPACIDAD a la derecha
                  if (!widget.isPro)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.vibrate();
                        _UpgradeModal.show(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: ExodoColors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: ExodoColors.amber.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded, size: 12, color: ExodoColors.amber),
                            const SizedBox(width: 3),
                            Text(
                              'MÁS CAPACIDAD',
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

// Regla 9: Pensando con puntos cambiando de tamaño aleatoriamente
class _ThinkingBubble extends StatelessWidget {
  final Animation<double> pulseAnim;
  const _ThinkingBubble({required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RandomScalingDotSphere(animation: pulseAnim, size: 24),
            const SizedBox(width: 10),
            Text(
              'Exodo razonando...',
              style: GoogleFonts.jetBrainsMono(fontSize: 12, color: ExodoColors.amber, fontWeight: FontWeight.w500),
            ),
          ],
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
      // Regla 13: Chat del usuario en rectángulo simple SIN colita ("sale de mi")
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isLight ? const Color(0xFF221E1A) : const Color(0xFF282420),
            borderRadius: BorderRadius.circular(20), // ¡Simétrico completamente sin colita ni contorno!
          ),
          child: MarkdownBody(
            data: message.content,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: GoogleFonts.inter(fontSize: 15, color: Colors.white),
            ),
          ),
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
            Text(_isDeviceEnglish(context) ? 'Intent: ${message.intentDetected}' : 'Intención: ${message.intentDetected}', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: ExodoColors.amber.withOpacity(0.8))),
          ],
        ],
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
                    _UpgradeModal.show(context);
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
                        color: active ? ExodoColors.amber.withOpacity(0.18) : (isLight ? const Color(0xFFEFECE4) : const Color(0xFF3A352F)),
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
                Icon(Icons.psychology_rounded, size: 15, color: ExodoColors.amber.withOpacity(0.8)),
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
            boxShadow: [BoxShadow(color: ExodoColors.amber.withOpacity(op), blurRadius: blur, spreadRadius: 1)],
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
                                          decoration: BoxDecoration(color: ExodoColors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
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
                          onPressed: () {},
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

class _GuestOfflineStage extends StatelessWidget {
  const _GuestOfflineStage();

  @override
  Widget build(BuildContext context) {
    final isEn = _isDeviceEnglish(context);
    final state = context.watch<AppState>();

    void goToLogin() async {
      HapticFeedback.vibrate();
      state.selectModelOption(exodoModels[0]);
      await SupabaseService.signOut();
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 76, color: ExodoColors.amber),
            const SizedBox(height: 24),
            Text(
              isEn ? "You're offline" : "Estás desconectado",
              style: GoogleFonts.syne(fontSize: 30, fontWeight: FontWeight.bold, color: ExodoColors.textPrimary),
            ),
            const SizedBox(height: 18),
            if (isEn)
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.inter(fontSize: 15.5, color: ExodoColors.textSecondary, height: 1.55),
                  children: [
                    const TextSpan(text: "To continue sending messages, "),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: goToLogin,
                        child: Text(
                          "upgrade",
                          style: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.bold, color: ExodoColors.amber, decoration: TextDecoration.underline, decorationColor: ExodoColors.amber),
                        ),
                      ),
                    ),
                    const TextSpan(text: " your plan to Pro or "),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: goToLogin,
                        child: Text(
                          "sign in",
                          style: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.bold, color: ExodoColors.amber, decoration: TextDecoration.underline, decorationColor: ExodoColors.amber),
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
                  style: GoogleFonts.inter(fontSize: 15.5, color: ExodoColors.textSecondary, height: 1.55),
                  children: [
                    const TextSpan(text: "Para seguir enviando mensajes, "),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: goToLogin,
                        child: Text(
                          "actualice",
                          style: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.bold, color: ExodoColors.amber, decoration: TextDecoration.underline, decorationColor: ExodoColors.amber),
                        ),
                      ),
                    ),
                    const TextSpan(text: " su plan a Pro o "),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: goToLogin,
                        child: Text(
                          "inicie sesión",
                          style: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.bold, color: ExodoColors.amber, decoration: TextDecoration.underline, decorationColor: ExodoColors.amber),
                        ),
                      ),
                    ),
                    const TextSpan(text: "."),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}




