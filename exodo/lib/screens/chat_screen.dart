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
  late AnimationController _logoRotationCtrl;

  @override
  void initState() {
    super.initState();
    _thinkingAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _logoRotationCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _thinkingAnimCtrl.dispose();
    _logoRotationCtrl.dispose();
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
      backgroundColor: ExodoColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _ModelSelectorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _scrollToBottom();

    return Scaffold(
      drawer: const DrawerMenu(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, size: 26),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const SizedBox.shrink(), // Diseño original: barra superior limpia y minimalista
        actions: [
          IconButton(
            icon: Icon(
              state.isIncognito ? Icons.privacy_tip : Icons.privacy_tip_outlined,
              color: state.isIncognito ? ExodoColors.amber : ExodoColors.textSecondary,
              size: 24,
            ),
            onPressed: () {
              state.toggleIncognito();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(state.isIncognito ? '🕵️ Modo incógnito activo (no guarda DB)' : '💬 Modo normal activo'),
                duration: const Duration(seconds: 2),
              ));
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Resplandor atmosférico superior derecho (Glow original de tu diseño)
          Positioned(
            top: -120,
            right: -100,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFD97151).withOpacity(0.16), // Coral cálido
                    const Color(0xFF6F5CF6).withOpacity(0.10), // Violeta sutil
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Contenido principal
          Column(
            children: [
              // Barra sutil de tokens en la parte superior
              _TokenProgressBar(used: state.tokensUsed, limit: state.tokensLimit),

              // Stage principal o mensajes
              Expanded(
                child: state.currentMessages.isEmpty
                    ? _OriginalDesignStage(
                        anim: _logoRotationCtrl,
                        fullName: state.profile?.fullName,
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: state.currentMessages.length,
                        itemBuilder: (context, index) {
                          final msg = state.currentMessages[index];
                          if (msg.isThinking) {
                            return _ThinkingBubble(anim: _thinkingAnimCtrl);
                          }
                          return _MessageBubble(message: msg);
                        },
                      ),
              ),

              // Banner flotante Pro Strip (Más capacidad con Exodo Pro)
              const _ProBannerStrip(),

              // Caja de chat flotante con borde degradado neón
              _FloatingComposerBox(
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
        ],
      ),
    );
  }
}

class _OriginalDesignStage extends StatelessWidget {
  final Animation<double> anim;
  final String? fullName;
  const _OriginalDesignStage({required this.anim, required this.fullName});

  String _getGreeting() {
    final firstName = (fullName != null && fullName!.trim().isNotEmpty)
        ? fullName!.trim().split(' ').first
        : 'David';
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días, $firstName';
    if (hour < 19) return 'Buenas tardes, $firstName';
    return 'Buenas noches, $firstName';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo giratorio de apertura geométrica original
            AnimatedBuilder(
              animation: anim,
              builder: (context, child) => Transform.rotate(
                angle: anim.value * 2 * 3.1415926535,
                child: child,
              ),
              child: const _ApertureLogoWidget(size: 76),
            ),
            const SizedBox(height: 28),
            Text(
              _getGreeting(),
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: ExodoColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Exodo by Behavior',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: ExodoColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApertureLogoWidget extends StatelessWidget {
  final double size;
  const _ApertureLogoWidget({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AperturePainter(),
      ),
    );
  }
}

class _AperturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paintLine = Paint()
      ..color = const Color(0xFFD97151) // Coral cálido original
      ..strokeWidth = size.width * (9 / 128)
      ..strokeCap = StrokeCap.round;

    final r = size.width * (48 / 128);
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * (3.1415926535 / 4));
      canvas.drawLine(Offset(0, -r), Offset(0, r), paintLine);
      canvas.restore();
    }

    final paintDiamond = Paint()..color = const Color(0xFFF2A076); // Durazno luminoso
    final drX = size.width * (15 / 128);
    final drY = size.width * (34 / 128);
    final path = Path()
      ..moveTo(center.dx, center.dy - drY)
      ..lineTo(center.dx + drX, center.dy)
      ..lineTo(center.dx, center.dy + drY)
      ..lineTo(center.dx - drX, center.dy)
      ..close();
    canvas.drawPath(path, paintDiamond);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProBannerStrip extends StatefulWidget {
  const _ProBannerStrip();
  @override
  State<_ProBannerStrip> createState() => _ProBannerStripState();
}

class _ProBannerStripState extends State<_ProBannerStrip> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF221E1A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ExodoColors.border),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Más capacidad con Exodo Pro',
              style: TextStyle(color: Color(0xFFE5E1DA), fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('⚡ Plan Exodo Pro (Hazak) seleccionado')),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Actualizar',
              style: TextStyle(color: Color(0xFF8B7FF8), fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _dismissed = true),
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(Icons.close, size: 16, color: ExodoColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingComposerBox extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onModelTap;
  const _FloatingComposerBox({
    required this.controller,
    required this.onSend,
    required this.onModelTap,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      margin: const EdgeInsets.only(left: 14, right: 14, bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFD97151), // Coral neón
            Color(0xFFC9933A), // Ámbar
            Color(0xFF6F5CF6), // Azul violeta Pro
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97151).withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1.5), // Grosor del borde resplandeciente
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF161412), // Superficie negra elegante
          borderRadius: BorderRadius.circular(30.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              maxLines: 4,
              minLines: 1,
              style: const TextStyle(fontSize: 16, color: ExodoColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Pregunta lo que quieras...',
                hintStyle: TextStyle(color: Color(0xFF7B7872), fontSize: 16),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // Botón redondo +
                _ActionCircleBtn(
                  icon: Icons.add,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('📎 Menú para adjuntar documentos')),
                    );
                  },
                ),
                const SizedBox(width: 8),
                // Pastilla selectora de modelo (G1.3 v)
                GestureDetector(
                  onTap: onModelTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25211D),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: ExodoColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          state.selectedModel.title,
                          style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.bold, color: ExodoColors.textPrimary),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, size: 16, color: ExodoColors.textSecondary),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // Micrófono
                IconButton(
                  icon: const Icon(Icons.mic_none, color: ExodoColors.textSecondary),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('🎙️ Entrada de voz lista')),
                    );
                  },
                ),
                // Botón redondo blanco de Enviar
                GestureDetector(
                  onTap: onSend,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: ExodoColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_upward, size: 20, color: Color(0xFF141210)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ActionCircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Color(0xFF25211D),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: ExodoColors.textSecondary),
      ),
    );
  }
}

class _TokenProgressBar extends StatelessWidget {
  final int used;
  final int limit;
  const _TokenProgressBar({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    final progress = (used / limit).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: ExodoColors.border,
                valueColor: const AlwaysStoppedAnimation(ExodoColors.amber),
                minHeight: 3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('$used / $limit tokens', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  final Animation<double> anim;
  const _ThinkingBubble({required this.anim});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) => Opacity(
          opacity: 0.4 + (anim.value * 0.6),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: ExodoColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ExodoColors.amber.withOpacity(anim.value)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.blur_on, size: 18, color: ExodoColors.amber),
                const SizedBox(width: 8),
                Text('Éxodo pensando...', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ExodoColors.amber)),
              ],
            ),
          ),
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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF282420) : ExodoColors.surface,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: isUser ? Radius.zero : const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(18) : Radius.zero,
          ),
          border: isUser ? Border.all(color: ExodoColors.amber.withOpacity(0.3)) : Border.all(color: ExodoColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: message.content,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: ExodoColors.textPrimary,
                ),
                code: TextStyle(backgroundColor: ExodoColors.background.withOpacity(0.5), fontFamily: 'JetBrains Mono'),
              ),
            ),
            if (!isUser && message.intentDetected != null) ...[
              const SizedBox(height: 8),
              Text('Intención: ${message.intentDetected}', style: TextStyle(fontSize: 10, color: ExodoColors.amber.withOpacity(0.8))),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelSelectorSheet extends StatelessWidget {
  const _ModelSelectorSheet();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Modelos Éxodo', style: Theme.of(context).textTheme.titleLarge),
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
                  Text(m.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text(m.subtitle, style: TextStyle(fontSize: 12, color: active ? ExodoColors.amber : ExodoColors.textSecondary)),
                ],
              ),
              subtitle: Text(m.description, style: Theme.of(context).textTheme.bodySmall),
              trailing: active ? const Icon(Icons.check, color: ExodoColors.amber) : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: active ? ExodoColors.amberGlow : Colors.transparent,
            );
          }),
        ],
      ),
    );
  }
}

