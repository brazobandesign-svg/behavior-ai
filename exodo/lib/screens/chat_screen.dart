import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/drawer_menu.dart';
import '../theme/exodo_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _thinkingAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    _ambientBgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _thinkingAnimCtrl.dispose();
    _ambientBgCtrl.dispose();
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _ModelSelectorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode;
    _scrollToBottom();

    return Scaffold(
      drawer: const DrawerMenu(),
      body: _AmbientBackground(
        animation: _ambientBgCtrl,
        child: SafeArea(
          child: Column(
            children: [
              // Barra superior minimalista y limpia
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    // Menú Profile estilo Library (3 líneas escalonadas)
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

                    // Regla incógnito: si está activo, oculta New Chat y Dark mode, y muestra "incognito chat"
                    if (state.isIncognito) ...[
                      const Spacer(),
                      Text(
                        Localizations.localeOf(context).languageCode == 'en' ? 'incognito chat' : 'chat incógnito',
                        style: GoogleFonts.jetBrainsMono(fontSize: 12, color: ExodoColors.amber, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                    ] else ...[
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.chat_bubble_outline_rounded, size: 21, color: isLight ? Colors.black87 : ExodoColors.textSecondary),
                        tooltip: 'Nuevo chat',
                        onPressed: () => state.startNewChat(),
                      ),
                      IconButton(
                        icon: Icon(state.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 22, color: isLight ? Colors.black87 : ExodoColors.textSecondary),
                        tooltip: 'Cambiar tema',
                        onPressed: () => state.toggleTheme(),
                      ),
                    ],

                    // Botón de Incógnito (siempre accesible)
                    IconButton(
                      icon: Icon(state.isIncognito ? Icons.visibility_off : Icons.visibility_off_outlined, size: 22, color: state.isIncognito ? ExodoColors.amber : (isLight ? Colors.black87 : ExodoColors.textSecondary)),
                      tooltip: 'Modo incógnito',
                      onPressed: () {
                        state.toggleIncognito();
                      },
                    ),
                  ],
                ),
              ),

              // Conteo de tokens interactivo con menú emergente justo debajo en tiempo real
              _TokenProgressBar(used: state.tokensUsed, limit: state.tokensLimit),

              // Stage principal o lista de mensajes
              Expanded(
                child: state.currentMessages.isEmpty
                    ? _OriginalDesignStage(fullName: state.profile?.fullName, isIncognito: state.isIncognito)
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: state.currentMessages.length,
                        itemBuilder: (context, index) {
                          final msg = state.currentMessages[index];
                          if (msg.isThinking) {
                            return _ThinkingBubble(animCtrl: _thinkingAnimCtrl);
                          }
                          return _MessageBubble(message: msg);
                        },
                      ),
              ),

              // Composer entrelazado supremo
              _InterlockingComposerArea(
                controller: _inputCtrl,
                onSend: () {
                  final text = _inputCtrl.text;
                  if (text.trim().isEmpty) return;
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

// Regla 2: Ambiente ámbar solo abajo en modo oscuro; Modo claro sin animación plano
class _AmbientBackground extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _AmbientBackground({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode;

    if (isLight) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFFBF9F5),
        child: child,
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(0.0, 1.0 + (t * 0.15)),
              end: const Alignment(0.0, -0.1),
              colors: [
                const Color(0xFFE5A93C).withOpacity(0.16 + (t * 0.08)),
                const Color(0xFF0E0C0A),
              ],
            ),
          ),
          child: child,
        );
      },
    );
  }
}

// Stage sin animación en el centro o icono de incógnito
class _OriginalDesignStage extends StatelessWidget {
  final String? fullName;
  final bool isIncognito;
  const _OriginalDesignStage({required this.fullName, required this.isIncognito});

  String _getGreeting() {
    final firstName = (fullName != null && fullName!.trim().isNotEmpty)
        ? fullName!.trim().split(' ').first
        : 'BRAZOBAN';
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días,\n$firstName';
    if (hour < 19) return 'Buenas tardes,\n$firstName';
    return 'Buenas noches,\n$firstName';
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    // Regla incógnito: en lugar del saludo, icono y mensaje central
    if (isIncognito) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.visibility_off, size: 78, color: ExodoColors.amber),
              const SizedBox(height: 18),
              Text(
                isEn ? "incognito chats aren't saved." : "los chats incógnito no se guardan.",
                textAlign: TextAlign.center,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isLight ? Colors.black87 : ExodoColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Regla: Saludo en tipografía JetBrains Mono
            Text(
              _getGreeting(),
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),

            // Regla: Exodo by Behavior en tipografía Syne
            Text(
              'Exodo by Behavior',
              style: GoogleFonts.syne(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: ExodoColors.amber,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Composer con adjuntos reales, voz nativa y botones súper pegados a la derecha
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

class _InterlockingComposerAreaState extends State<_InterlockingComposerArea> {
  bool _showTab2 = true;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  String _getPlaceholder(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    if (_isListening) return lang == 'en' ? 'Listening...' : 'Escuchando...';
    if (lang == 'en') return 'Reply to Exodo...';
    return 'Hablar con Exodo...';
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Añadir adjunto', style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library, color: ExodoColors.amber),
                title: const Text('Galería de fotos'),
                subtitle: const Text('Permiso estándar para acceder a tu galería'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picker = ImagePicker();
                  final image = await picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    widget.controller.text += " [📸 Foto adjunta: ${image.name}]";
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: ExodoColors.amber),
                title: const Text('Cámara'),
                subtitle: const Text('Tomar una foto con tu cámara'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picker = ImagePicker();
                  final photo = await picker.pickImage(source: ImageSource.camera);
                  if (photo != null) {
                    widget.controller.text += " [📸 Foto capturada: ${photo.name}]";
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder, color: ExodoColors.amber),
                title: const Text('Archivos / Files'),
                subtitle: const Text('Seleccionar documentos o PDF en tu dispositivo'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final res = await FilePicker.platform.pickFiles();
                  if (res != null && res.files.isNotEmpty) {
                    widget.controller.text += " [📄 Archivo adjunto: ${res.files.first.name}]";
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleVoiceListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (result) {
            setState(() {
              widget.controller.text = result.recognizedWords;
            });
          },
          localeId: Localizations.localeOf(context).languageCode == 'en' ? 'en_US' : 'es_ES',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Permiso de micrófono requerido por el sistema operativo')));
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode;

    final tab1Bg = isLight ? const Color(0xFFEFECE4) : const Color(0xFF161412);
    final tab1Text = isLight ? const Color(0xFF161412) : Colors.white;
    final tab2Bg = isLight ? const Color(0xFF161412) : const Color(0xFFEFECE4);
    final tab2Text = isLight ? const Color(0xFFD5D1C9) : const Color(0xFF55514C);

    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Tab 2 superior
          if (_showTab2)
            Positioned(
              top: -36,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.86,
                padding: const EdgeInsets.fromLTRB(16, 7, 14, 20),
                decoration: BoxDecoration(
                  color: tab2Bg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border.all(color: isLight ? const Color(0xFF332E29) : const Color(0xFFDCD5C5)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Limites mas altos con XPi',
                        style: GoogleFonts.jetBrainsMono(color: tab2Text, fontSize: 12.0, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚡ Plan XPi seleccionado'))),
                        child: Text(
                          'Actualizar',
                          style: GoogleFonts.jetBrainsMono(color: ExodoColors.amber, fontWeight: FontWeight.bold, fontSize: 12.0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: () => setState(() => _showTab2 = false),
                        child: Icon(Icons.close, size: 15, color: tab2Text.withOpacity(0.7)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Tab 1 principal
          Container(
            decoration: BoxDecoration(
              color: tab1Bg,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: isLight ? const Color(0xFFDCD5C5) : ExodoColors.border),
            ),
            // Botones súper pegados al extremo derecho
            padding: const EdgeInsets.fromLTRB(18, 8, 2, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: widget.controller,
                  maxLines: 4,
                  minLines: 1,
                  style: TextStyle(fontSize: 16, color: tab1Text),
                  decoration: InputDecoration(
                    hintText: _getPlaceholder(context),
                    hintStyle: GoogleFonts.inter(color: isLight ? const Color(0xFF8C8880) : const Color(0xFF7B7872), fontSize: 16),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Botón + con menú real de fotos y archivos
                    InkWell(
                      onTap: _showAttachmentMenu,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: isLight ? const Color(0xFFDFDACE).withOpacity(0.6) : const Color(0xFF25211D), shape: BoxShape.circle),
                        child: Icon(Icons.add, size: 20, color: isLight ? const Color(0xFF161412) : Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Selector de modelo
                    Flexible(
                      child: GestureDetector(
                        onTap: widget.onModelTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: isLight ? const Color(0xFFE5DFCF) : const Color(0xFF25211D),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isLight ? const Color(0xFFDCD5C5) : ExodoColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  state.selectedModel.title,
                                  style: GoogleFonts.jetBrainsMono(fontSize: 12.0, fontWeight: FontWeight.bold, color: tab1Text),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.keyboard_arrow_down, size: 16, color: tab1Text.withOpacity(0.7)),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Swap dinámico pegado milimétricamente al borde derecho
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: widget.controller,
                      builder: (context, val, _) {
                        final hasText = val.text.trim().isNotEmpty;

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Micrófono nativo real
                            IconButton(
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                _isListening ? Icons.mic : Icons.mic_none,
                                color: _isListening
                                    ? ExodoColors.amber
                                    : (hasText ? (isLight ? Colors.black38 : ExodoColors.textSecondary) : tab1Text),
                              ),
                              onPressed: _toggleVoiceListening,
                            ),

                            // Botón enviar blanco hueso pegado a derecha
                            if (hasText)
                              GestureDetector(
                                onTap: widget.onSend,
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  margin: const EdgeInsets.only(left: 2, right: 1),
                                  decoration: const BoxDecoration(color: Color(0xFFFBF9F5), shape: BoxShape.circle),
                                  child: const Icon(Icons.arrow_upward, size: 19, color: Color(0xFF141210)),
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
        ],
      ),
    );
  }
}

// Conteo de tokens interactivo con menú desplegable inferior en tiempo real
class _TokenProgressBar extends StatefulWidget {
  final int used;
  final int limit;
  const _TokenProgressBar({required this.used, required this.limit});

  @override
  State<_TokenProgressBar> createState() => _TokenProgressBarState();
}

class _TokenProgressBarState extends State<_TokenProgressBar> {
  bool _expanded = false;
  late Timer _timer;
  String _timeLeft = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final diff = nextMidnight.difference(now);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (mounted) {
      setState(() {
        _timeLeft = '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final used = widget.used;
    final limit = widget.limit;
    final remaining = (limit - used).clamp(0, limit);
    final progress = (used / limit).clamp(0.0, 1.0);
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFFF2ECE1) : ExodoColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isLight ? const Color(0xFFE5DECF) : ExodoColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: isLight ? const Color(0xFFE5DECF) : ExodoColors.border,
                      valueColor: const AlwaysStoppedAnimation(ExodoColors.amber),
                      minHeight: 3.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$used / $limit tokens',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: isLight ? Colors.black87 : ExodoColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 15, color: isLight ? Colors.black54 : ExodoColors.textSecondary),
              ],
            ),
          ),
        ),

        // Barra desplegable justo debajo con cuenta regresiva en tiempo real
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFFEBE4D7) : const Color(0xFF221E1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ExodoColors.amber.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _infoPill('Consumido', '$used tk', isLight),
                _infoPill('Disponible', '$remaining tk', isLight),
                _infoPill('Reinicio en', _timeLeft, isLight, isAmber: true),
              ],
            ),
          ),
      ],
    );
  }

  Widget _infoPill(String label, String value, bool isLight, {bool isAmber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 9, color: isLight ? Colors.black54 : ExodoColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: isAmber ? ExodoColors.amber : (isLight ? Colors.black87 : Colors.white))),
      ],
    );
  }
}

// Pensando con icono que GIRA
class _ThinkingBubble extends StatelessWidget {
  final AnimationController animCtrl;
  const _ThinkingBubble({required this.animCtrl});

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
            RotationTransition(
              turns: animCtrl,
              child: const Icon(Icons.blur_on, size: 22, color: ExodoColors.amber),
            ),
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

// Estilo de burbujas tipo Claude
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
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isLight ? const Color(0xFF221E1A) : const Color(0xFF282420),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ExodoColors.amber.withOpacity(0.35)),
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
            Text('Intención: ${message.intentDetected}', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: ExodoColors.amber.withOpacity(0.8))),
          ],
        ],
      ),
    );
  }
}

// Hoja de selección de modelos
class _ModelSelectorSheet extends StatelessWidget {
  const _ModelSelectorSheet();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: isLight ? Colors.black26 : ExodoColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('Modelos Exodo', style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.bold, color: isLight ? Colors.black87 : ExodoColors.textPrimary)),
          const SizedBox(height: 16),
          ...exodoModels.map((m) {
            final active = state.selectedModel.id == m.id;
            return ListTile(
              onTap: () {
                state.selectModelOption(m);
                Navigator.pop(context);
              },
              leading: Icon(Icons.bolt, color: active ? ExodoColors.amber : ExodoColors.textSecondary),
              title: Row(
                children: [
                  Text(m.title, style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold, fontSize: 14, color: isLight ? Colors.black87 : ExodoColors.textPrimary)),
                  const SizedBox(width: 8),
                  Text(m.subtitle, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: active ? ExodoColors.amber : ExodoColors.textSecondary)),
                ],
              ),
              subtitle: Text(m.description, style: GoogleFonts.inter(fontSize: 12, color: ExodoColors.textSecondary)),
              trailing: active ? const Icon(Icons.check, color: ExodoColors.amber) : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              tileColor: active ? ExodoColors.amber.withOpacity(isLight ? 0.12 : 0.18) : Colors.transparent,
            );
          }),
        ],
      ),
    );
  }
}
