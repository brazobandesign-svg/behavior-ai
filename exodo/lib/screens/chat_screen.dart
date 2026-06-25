import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/drawer_menu.dart';
import '../theme/exodo_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late AnimationController _thinkingAnimCtrl;

  @override
  void initState() {
    super.initState();
    _thinkingAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _thinkingAnimCtrl.dispose();
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
          builder: (ctx) => IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(ctx).openDrawer()),
        ),
        title: GestureDetector(
          onTap: _showModelSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: ExodoColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ExodoColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.selectedModel.title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 6),
                Text(state.selectedModel.subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ExodoColors.textSecondary)),
                const Icon(Icons.keyboard_arrow_down, size: 16, color: ExodoColors.textSecondary),
              ],
            ),
          ),
        ),
        actions: [
          // Regla: Botón de incógnito que altera estado visual
          IconButton(
            icon: Icon(
              state.isIncognito ? Icons.privacy_tip : Icons.privacy_tip_outlined,
              color: state.isIncognito ? ExodoColors.amber : ExodoColors.textSecondary,
            ),
            onPressed: () {
              state.toggleIncognito();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(state.isIncognito ? '🕵️ Modo incógnito activo (no guarda DB)' : '💬 Modo normal activo'),
                duration: const Duration(seconds: 2),
              ));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de progreso de tokens en tiempo real
          _TokenProgressBar(used: state.tokensUsed, limit: state.tokensLimit),

          // Lista de chat
          Expanded(
            child: state.currentMessages.isEmpty
                ? _WelcomePlaceholder(modelName: state.selectedModel.subtitle)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
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

          // Input field
          _ChatInputBox(
            controller: _inputCtrl,
            onSend: () {
              final text = _inputCtrl.text;
              _inputCtrl.clear();
              state.sendUserMessage(text);
            },
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: ExodoColors.surface,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: ExodoColors.border,
                valueColor: const AlwaysStoppedAnimation(ExodoColors.amber),
                minHeight: 4,
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
          color: isUser ? ExodoColors.amber : ExodoColors.surface,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: isUser ? Radius.zero : const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(18) : Radius.zero,
          ),
          border: isUser ? null : Border.all(color: ExodoColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: message.content,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isUser ? ExodoColors.background : ExodoColors.textPrimary,
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

class _WelcomePlaceholder extends StatelessWidget {
  final String modelName;
  const _WelcomePlaceholder({required this.modelName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, size: 48, color: ExodoColors.amber),
          const SizedBox(height: 16),
          Text('¿En qué trabajamos hoy?', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Modelo activo: $modelName', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ExodoColors.amber)),
        ],
      ),
    );
  }
}

class _ChatInputBox extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _ChatInputBox({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(color: ExodoColors.background, border: Border(top: BorderSide(color: ExodoColors.border))),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.mic_none, color: ExodoColors.textSecondary),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎙️ Entrada de micrófono preparada para Voz (Masculino/Femenino)')));
              },
            ),
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 4,
                minLines: 1,
                decoration: const InputDecoration(hintText: 'Pregunta a Éxodo...', contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: ExodoColors.amber,
              child: IconButton(icon: const Icon(Icons.arrow_upward, color: ExodoColors.background), onPressed: onSend),
            ),
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

    return Padding(
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
