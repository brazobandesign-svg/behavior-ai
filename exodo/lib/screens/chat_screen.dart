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
  late AnimationController _logoRotCtrl;

  @override
  void initState() {
    super.initState();
    _thinkingAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _ambientBgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat(reverse: true);
    _logoRotCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _thinkingAnimCtrl.dispose();
    _ambientBgCtrl.dispose();
    _logoRotCtrl.dispose();
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
      // Fondo animado ambiental a pantalla completa (Regla 2)
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
                    // Regla 1: Menú Profile estilo Library (3 líneas, la última más corta)
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

                    // Regla 3: Íconos de Incógnito, Dark mode y Nuevo chat
                    // 1. Incógnito
                    IconButton(
                      icon: Icon(
                        state.isIncognito ? Icons.privacy_tip : Icons.privacy_tip_outlined,
                        size: 22,
                        color: state.isIncognito ? ExodoColors.amber : (isLight ? Colors.black54 : ExodoColors.textSecondary),
                      ),
                      tooltip: 'Modo incógnito',
                      onPressed: () {
                        state.toggleIncognito();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(state.isIncognito ? '🕵️ Modo incógnito activo (no guarda DB)' : '💬 Modo normal activo'),
                          duration: const Duration(seconds: 2),
                        ));
                      },
                    ),

                    // 2. Dark / Light Mode
                    IconButton(
                      icon: Icon(
                        state.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                        size: 22,
                        color: isLight ? Colors.black54 : ExodoColors.textSecondary,
                      ),
                      tooltip: 'Cambiar tema',
                      onPressed: () => state.toggleTheme(),
                    ),

                    // 3. Nuevo Chat
                    IconButton(
                      icon: Icon(
                        Icons.add_comment_outlined,
                        size: 22,
                        color: isLight ? Colors.black54 : ExodoColors.textSecondary,
                      ),
                      tooltip: 'Nuevo chat',
                      onPressed: () => state.startNewChat(),
                    ),
                  ],
                ),
              ),

              // Regla 4: Conteo de tokens sutil dentro de un rectángulo con bordes curvos
              _TokenProgressBar(used: state.tokensUsed, limit: state.tokensLimit),

              // Stage principal o lista de mensajes (Regla 8: desaparece al enviar mensaje)
              Expanded(
                child: state.currentMessages.isEmpty
                    ? _OriginalDesignStage(
                        rotAnim: _logoRotCtrl,
                        fullName: state.profile?.fullName,
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: state.currentMessages.length,
                        itemBuilder: (context, index) {
                          final msg = state.currentMessages[index];
                          if (msg.isThinking) {
                            // Regla 9: Animación thinking con el logo de login girando
                            return _ThinkingBubble(anim: _thinkingAnimCtrl);
                          }
                          return _MessageBubble(message: msg);
                        },
                      ),
              ),

              // Regla 7, 10, 11: Tab 1 y Tab 2 entrelazados con resplandor opuesto y botón reactivo
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

// Fondo ambiental a pantalla completa sin cortes (Regla 2, 13)
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
              begin: Alignment(-1.0 + (t * 0.6), -1.0),
              end: Alignment(1.0 - (t * 0.6), 1.0),
              colors: isLight
                  ? [
                      const Color(0xFFFBF9F5), // Blanco yeso o hueso cremoso
                      const Color(0xFFF4EFE6),
                      Color.lerp(const Color(0xFFEFE9DE), const Color(0xFFE7DFD0), t)!,
                    ]
                  : [
                      const Color(0xFF0E0C0A), // Negro Cálido
                      Color.lerp(const Color(0xFF18101C), const Color(0xFF1E1410), t)!, // Ambiente degradado sutil
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
  final Animation<double> rotAnim;
  final String? fullName;
  const _OriginalDesignStage({required this.rotAnim, required this.fullName});

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
            // Regla 5: Logo girando de la pantalla de login (Esfera de puntos dorados)
            AnimatedBuilder(
              animation: rotAnim,
              builder: (context, child) => Transform.rotate(
                angle: rotAnim.value * 2 * 3.1415926535,
                child: child,
              ),
              child: const Icon(Icons.blur_on, size: 76, color: ExodoColors.amber),
            ),
            const SizedBox(height: 24),

            // Regla 6: Saludo más pequeño
            Text(
              _getGreeting(),
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                fontSize: 23, // Más pequeño
                fontWeight: FontWeight.bold,
                color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),

            // Regla 6: Tipografía de "continuar con google" (JetBrains Mono oficial) para Exodo by Behavior
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

// Regla 7, 10, 11: Estructura entrelazada de Tab 1 y Tab 2
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode;

    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Regla 7: Tab 2 (Límites más altos con XPi) sobresaliendo arriba de Tab 1
          if (_showTab2)
            Positioned(
              top: -36, // Sobresale arriba
              child: Container(
                width: MediaQuery.of(context).size.width * 0.76, // Menos ancho que Tab 1
                padding: const EdgeInsets.fromLTRB(18, 8, 14, 20), // Padding inferior oculto dentro de Tab 1
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xFFEFECE4) : const Color(0xFF221E1A),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border.all(color: isLight ? const Color(0xFFDCD5C5) : ExodoColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Limites mas altos con XPi',
                      style: GoogleFonts.jetBrainsMono( // Misma tipografía oficial
                        color: isLight ? const Color(0xFF55514C) : const Color(0xFFD5D1C9),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('⚡ Plan XPi seleccionado')),
                        );
                      },
                      child: Text(
                        'Actualizar',
                        style: GoogleFonts.jetBrainsMono(
                          color: ExodoColors.amber, // Color ámbar de la marca
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => setState(() => _showTab2 = false),
                      child: Icon(Icons.close, size: 14, color: isLight ? Colors.black45 : ExodoColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),

          // Regla 10: Tab 1 (Principal) sin neón, con resplandor opuesto en esquinas
          Container(
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF161412),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: isLight ? const Color(0xFFE5DECF) : ExodoColors.border),
              // Resplandor opuesto diagonal original
              boxShadow: [
                BoxShadow(
                  color: ExodoColors.amber.withOpacity(isLight ? 0.08 : 0.12),
                  blurRadius: 26,
                  offset: const Offset(-8, -8), // Esquina superior izquierda
                ),
                BoxShadow(
                  color: (isLight ? const Color(0xFF0D8B8B) : const Color(0xFF6F5CF6)).withOpacity(isLight ? 0.05 : 0.08),
                  blurRadius: 26,
                  offset: const Offset(8, 8), // Esquina inferior derecha opuesta
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: widget.controller,
                  maxLines: 4,
                  minLines: 1,
                  style: TextStyle(fontSize: 16, color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Pregunta lo que quieras...',
                    hintStyle: GoogleFonts.inter(color: isLight ? const Color(0xFF9E9689) : const Color(0xFF7B7872), fontSize: 16),
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
                    // Botón circular +
                    InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📎 Menú de adjuntos listo')));
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isLight ? const Color(0xFFF2ECE1) : const Color(0xFF25211D),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.add, size: 20, color: isLight ? Colors.black87 : ExodoColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Selector de modelo
                    GestureDetector(
                      onTap: widget.onModelTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isLight ? const Color(0xFFF2ECE1) : const Color(0xFF25211D),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isLight ? const Color(0xFFE5DECF) : ExodoColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              state.selectedModel.title,
                              style: GoogleFonts.jetBrainsMono(fontSize: 12.5, fontWeight: FontWeight.bold, color: isLight ? Colors.black87 : ExodoColors.textPrimary),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down, size: 16, color: isLight ? Colors.black54 : ExodoColors.textSecondary),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Micrófono
                    IconButton(
                      icon: Icon(Icons.mic_none, color: isLight ? Colors.black54 : ExodoColors.textSecondary),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎙️ Entrada de voz lista')));
                      },
                    ),

                    // Regla 11: Botón de envío reactivo (Solo sale cuando hay texto/contenido)
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: widget.controller,
                      builder: (context, val, _) {
                        if (val.text.trim().isEmpty) return const SizedBox.shrink();
                        return GestureDetector(
                          onTap: widget.onSend,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.arrow_upward, size: 18, color: isLight ? Colors.white : const Color(0xFF141210)),
                          ),
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

// Regla 4: Conteo de tokens en rectángulo con bordes curvos
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

// Regla 9: Animación thinking con el logo geométrica oficial de login
class _ThinkingBubble extends StatelessWidget {
  final Animation<double> anim;
  const _ThinkingBubble({required this.anim});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : ExodoColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ExodoColors.amber.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: anim,
              builder: (context, child) => Transform.rotate(
                angle: anim.value * 2 * 3.1415926535,
                child: child,
              ),
              child: const Icon(Icons.blur_on, size: 22, color: ExodoColors.amber),
            ),
            const SizedBox(height: 0, width: 10),
            Text(
              'Éxodo razonando...',
              style: GoogleFonts.jetBrainsMono(fontSize: 12, color: ExodoColors.amber, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUser ? (isLight ? const Color(0xFF221E1A) : const Color(0xFF282420)) : (isLight ? Colors.white : ExodoColors.surface),
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: isUser ? Radius.zero : const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(18) : Radius.zero,
          ),
          border: isUser ? Border.all(color: ExodoColors.amber.withOpacity(0.3)) : Border.all(color: isLight ? const Color(0xFFE5DECF) : ExodoColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: message.content,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: GoogleFonts.inter(
                  fontSize: 15,
                  color: isUser ? Colors.white : (isLight ? const Color(0xFF171615) : ExodoColors.textPrimary),
                ),
                code: GoogleFonts.jetBrainsMono(backgroundColor: ExodoColors.background.withOpacity(0.3)),
              ),
            ),
            if (!isUser && message.intentDetected != null) ...[
              const SizedBox(height: 8),
              Text('Intención: ${message.intentDetected}', style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: ExodoColors.amber.withOpacity(0.8))),
            ],
          ],
        ),
      ),
    );
  }
}

// Regla 12: Hoja de modelos con indicador dot/barra superior y tipografía oficial JetBrains Mono
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
          // Regla 12: Dot/Barra superior deslizable
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isLight ? Colors.black26 : ExodoColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Text('Modelos Éxodo', style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.bold, color: isLight ? Colors.black87 : ExodoColors.textPrimary)),
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


