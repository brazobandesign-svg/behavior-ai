import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
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
  late AnimationController _pulseCtrl;

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

                    // Regla 3: Orden exacto -> 1ro New Chat, 2do Dark mode, 3ro Incognito (nuevos íconos)
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

                    // 3. Incógnito
                    IconButton(
                      icon: Icon(
                        state.isIncognito ? Icons.visibility_off : Icons.visibility_off_outlined,
                        size: 22,
                        color: state.isIncognito ? ExodoColors.amber : (isLight ? Colors.black87 : ExodoColors.textSecondary),
                      ),
                      tooltip: 'Modo incógnito',
                      onPressed: () {
                        state.toggleIncognito();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(state.isIncognito ? '🕵️ Modo incógnito activo (no guarda en DB)' : '💬 Modo normal activo'),
                          duration: const Duration(seconds: 2),
                        ));
                      },
                    ),
                  ],
                ),
              ),

              // Regla 4: Conteo de tokens en tarjeta curva sutil
              _TokenProgressBar(used: state.tokensUsed, limit: state.tokensLimit),

              // Stage principal o lista de mensajes (Regla 8)
              Expanded(
                child: state.currentMessages.isEmpty
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
                            // Regla 9: Pensando con puntos cambiando de tamaño aleatorio
                            return _ThinkingBubble(pulseAnim: _pulseCtrl);
                          }
                          return _MessageBubble(message: msg);
                        },
                      ),
              ),

              // Regla 7, 10, 11, 13, 14: Tab 1 y Tab 2 entrelazados supremos
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

// Regla 2: Fondo ambiental animado (Limpio en modo claro, sin mancha amarilla)
class _AnimatedAmbientBackground extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _AnimatedAmbientBackground({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + (t * 0.7), -1.0),
              end: Alignment(1.0 - (t * 0.7), 1.0),
              colors: isLight
                  ? [
                      const Color(0xFFFBF9F5), // Blanco yeso/hueso limpio
                      Color.lerp(const Color(0xFFF2F4F7), const Color(0xFFE5E9F0), t)!, // Onda gris plata/nieve limpia sin mancha amarilla
                      const Color(0xFFF8F9FA),
                    ]
                  : [
                      const Color(0xFF0E0C0A), // Negro Cálido
                      Color.lerp(const Color(0xFF1A1220), const Color(0xFF221610), t)!, // Resplandor atmosférico sutil
                      const Color(0xFF0A0908),
                    ],
            ),
          ),
          child: child,
        );
      },
    );
  }
}

class _OriginalDesignStage extends StatelessWidget {
  final Animation<double> pulseAnim;
  final String? fullName;
  const _OriginalDesignStage({required this.pulseAnim, required this.fullName});

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

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Regla 5: Esfera geométrica con cambio de tamaño POR PUNTOS aleatorio
            _RandomScalingDotSphere(animation: pulseAnim, size: 84),
            const SizedBox(height: 24),

            // Regla 6: Saludo de tamaño adecuado
            Text(
              _getGreeting(),
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),

            // Regla 6 & 12: Tipografía JetBrains Mono oficial y Exodo sin tilde
            Text(
              'Exodo by Behavior',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ExodoColors.amber,
                letterSpacing: 0.3,
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

class _InterlockingComposerAreaState extends State<_InterlockingComposerArea> {
  bool _showTab2 = true;

  String _getPlaceholder(BuildContext context) {
    // Regla 14: Detectar automáticamente idioma de dispositivo
    final lang = Localizations.localeOf(context).languageCode;
    if (lang == 'en') return 'Reply to Exodo...';
    return 'Hablar con Exodo...'; // Equivalente corto y elegante sin tilde
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Regla 7 & No mencionados: Tab 2 BLANCO PURO / HUESO CLARO en ambos modos (#EFECE4)
          if (_showTab2)
            Positioned(
              top: -36,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.86,
                padding: const EdgeInsets.fromLTRB(16, 7, 14, 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFECE4), // Blanco puro/hueso en modo dark y light estrictamente
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border.all(color: const Color(0xFFDCD5C5)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown, // ¡Garantiza 100% visible sin cortarse en cualquier pantalla!
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Limites mas altos con XPi',
                        style: GoogleFonts.jetBrainsMono(
                          color: const Color(0xFF55514C), // Texto oscuro elegante en fondo blanco
                          fontSize: 12.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('⚡ Plan XPi seleccionado')),
                          );
                        },
                        child: Text(
                          'Actualizar',
                          style: GoogleFonts.jetBrainsMono(
                            color: ExodoColors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: () => setState(() => _showTab2 = false),
                        child: const Icon(Icons.close, size: 15, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Regla 10 & 13: Tab 1 oscuro en ambos modos (#161412), SIN resplandor exterior (Regla 10 actualizada)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161412),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: ExodoColors.border),
            ),
            // Regla 11: Botones alineados pegados al borde derecho (padding right: 6px)
            padding: const EdgeInsets.fromLTRB(18, 8, 6, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: widget.controller,
                  maxLines: 4,
                  minLines: 1,
                  style: const TextStyle(fontSize: 16, color: Colors.white),
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
                  children: [
                    // Botón +
                    InkWell(
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📎 Menú de adjuntos listo'))),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(color: Color(0xFF25211D), shape: BoxShape.circle),
                        child: const Icon(Icons.add, size: 20, color: Colors.white70),
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
                            color: const Color(0xFF25211D),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: ExodoColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  state.selectedModel.title,
                                  style: GoogleFonts.jetBrainsMono(fontSize: 12.0, fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.keyboard_arrow_down, size: 16, color: ExodoColors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Regla 11: Swap dinámico de Micrófono y Enviar (Botón enviar blanco hueso, pegado a derecha)
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: widget.controller,
                      builder: (context, val, _) {
                        final hasText = val.text.trim().isNotEmpty;

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Micrófono
                            IconButton(
                              icon: Icon(Icons.mic_none, color: hasText ? ExodoColors.textSecondary : Colors.white70),
                              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎙️ Entrada de voz lista'))),
                            ),

                            // Botón enviar blanco hueso oficial regla*
                            if (hasText)
                              GestureDetector(
                                onTap: widget.onSend,
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  margin: const EdgeInsets.only(left: 2, right: 4),
                                  decoration: const BoxDecoration(color: Color(0xFFFBF9F5), shape: BoxShape.circle), // Blanco hueso
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

// Conteo de tokens en tarjeta curva sutil
class _TokenProgressBar extends StatelessWidget {
  final int used;
  final int limit;
  const _TokenProgressBar({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    final progress = (used / limit).clamp(0.0, 1.0);
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        ],
      ),
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
            borderRadius: BorderRadius.circular(20), // ¡Simétrico completamente sin colita!
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
            Text('Intención: ${message.intentDetected}', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: ExodoColors.amber.withOpacity(0.8))),
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




