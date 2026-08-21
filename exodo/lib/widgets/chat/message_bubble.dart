import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../services/supabase_service.dart';
import '../../theme/exodo_theme.dart';
import '../../l10n/app_i18n.dart';
import '../../data/artifacts/artifact.dart';
import '../../data/artifacts/artifact_parser.dart';
import '../artifacts/artifact_card.dart';
import 'model_selector.dart';

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

/// [Fix pantalla roja markdown] Sanea el texto antes de pasarlo a MarkdownBody

// Regla 9: Burbuja de "razonando" mientras la IA piensa.
// FIX v1.2.3: Se quita el Container con padding/decoration porque se
// renderizaba como una caja visible. Ahora es un Row directo sin
// envoltorio decorado, alineado a la izquierda como texto plano.
// [Punto 30 aviso]: junto al logo flecha, texto localizado vía
// `chat.thinking_label` (palabra suelta, sin puntos suspensivos).
// Opacidad fluctuante 25% ↔ 50% sincronizada con el pulseAnim del logo.
class ThinkingBubble extends StatelessWidget {
  final Animation<double> pulseAnim;
  const ThinkingBubble({super.key, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    // Selectores finos para evitar repintado durante streaming de chat
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);
    final isLight = !isDarkMode && !isIncognito;
    final logoColor = isLight ? ExodoColors.background : ExodoColors.amber;
    // Localización reactiva: cambia de idioma sin necesidad de reiniciar.
    final thinkingLabel = AppI18n.of(context).t('chat.thinking_label');
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: AnimatedBuilder(
          animation: pulseAnim,
          builder: (context, _) {
            final v = pulseAnim.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo flecha: opacidad 40% ↔ 100% (igual que antes).
                Opacity(
                  opacity: 0.4 + (v * 0.6).clamp(0.0, 0.6),
                  child: Image.asset(
                    'assets/images/exodo_arrow_logo.png',
                    width: 28,
                    height: 28,
                    color: logoColor,
                  ),
                ),
                const SizedBox(width: 8),
                // Texto localizado con fluctuación de opacidad 25% ↔ 50%
                // usando la misma curva del pulseAnim (2200ms, repeat reverse).
                Opacity(
                  opacity: 0.25 + (v * 0.25), // 0.25 (v=0) → 0.50 (v=1)
                  child: Text(
                    thinkingLabel,
                    style: TextStyle(
                      color: logoColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Inter',
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Regla 13: Estilo de burbujas tipo Claude (Usuario en rectángulo opuesto SIN colita, IA al descubierto)
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isLastAssistant;
  const MessageBubble({
    super.key,
    required this.message,
    this.isLastAssistant = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isLight = Theme.of(context).brightness == Brightness.light;
    final copyLabel = AppI18n.of(context).t('act.copy');
    final copiedLabel = AppI18n.of(context).t('act.copied');
    final likeLabel = AppI18n.of(context).t('act.like');
    final dislikeLabel = AppI18n.of(context).t('act.dislike');
    final shareLabel = AppI18n.of(context).t('act.share');
    final playLabel = AppI18n.of(context).t('act.play');

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.attachments.isNotEmpty) ...[
              for (final att in message.attachments)
                if (att.isImage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => Dialog(
                            backgroundColor: Colors.transparent,
                            insetPadding: const EdgeInsets.all(16),
                            child: Stack(
                              alignment: Alignment.topRight,
                              children: [
                                InteractiveViewer(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: _buildAttachmentFullScreen(att),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  onPressed: () => Navigator.pop(ctx),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _buildAttachmentThumbnail(att),
                      ),
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isLight ? Colors.black12 : Colors.white12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.insert_drive_file,
                          size: 18,
                          color: isLight ? Colors.black87 : Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            att.fileName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: isLight ? Colors.black87 : Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
            // FIX (no-mutación 2026-08-19): si el contenido del usuario está
            // vacío (o solo espacios) y hay adjuntos, renderizar SOLO la vista
            // del adjunto sin marco de texto vacío.
            if (message.content.trim().isNotEmpty)
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.82,
                ),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: isLight
                      ? Colors.white
                      : const Color(0xFF212121),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isLight ? Colors.black12 : Colors.transparent,
                    width: 1.0,
                  ),
                ),
                child: MarkdownBody(
                  data: _AssistantContentWithArtifacts._sanitizeMarkdown(message.content),
                  onTapLink: (text, href, title) {
                    if (href != null) {
                      final uri = Uri.tryParse(href);
                      if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  builders: {
                    'table': _TableElementBuilder(isLight),
                  },
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                      .copyWith(
                        p: TextStyle(
                          fontFamily: 'AnthropicSans',
                          fontSize: 15,
                          color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
                        ),
                        blockquotePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        blockquoteDecoration: BoxDecoration(
                          color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8),
                              width: 4,
                            ),
                          ),
                        ),
                        blockquote: TextStyle(
                          fontFamily: 'AnthropicSans',
                          fontSize: 14,
                          color: isLight ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                          fontStyle: FontStyle.italic,
                        ),
                        code: TextStyle(
                          fontFamily: 'AnthropicSans',
                          backgroundColor: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                          color: isLight ? const Color(0xFF0F172A) : const Color(0xFF38BDF8),
                          fontSize: 13.5,
                        ),
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
                _SmartCopyButton(
                  textToCopy: message.content,
                  color: isLight ? Colors.black38 : Colors.white38,
                  copyLabel: copyLabel,
                  copiedLabel: copiedLabel,
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
          (isLastAssistant && context.select<AppState, bool>((s) => s.isGenerating))
              ? SelectableText(
                  message.content,
                  style: TextStyle(
                    fontFamily: 'AnthropicSerif',
                    fontSize: 15.5,
                    color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
                    height: 1.45,
                  ),
                )
              : _AssistantContentWithArtifacts(
                  message: message,
                  isLight: isLight,
                  copyLabel: copyLabel,
                  copiedLabel: copiedLabel,
                ),
          if (message.isDegraded) ...[
            const SizedBox(height: 8),
            _EcoModeNotice(isLight: isLight),
          ],
          // [Fix LG V60 #1] Eliminado: el badge "Intención: VISION" era
          // un debug leak que mostraba el intent detectado al usuario final.
          // El intent sigue guardándose en BD/Supabase para analítica interna,
          // pero NO se renderiza en la burbuja.
          if (message.sources.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SourcesSheet(sources: message.sources),
          ],
          const SizedBox(height: 10),
          _MessageActionBar(
            message: message,
            copyLabel: copyLabel,
            copiedLabel: copiedLabel,
            likeLabel: likeLabel,
            dislikeLabel: dislikeLabel,
            shareLabel: shareLabel,
            playLabel: playLabel,
          ),
          if (isLastAssistant) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/Logo_behavior.png',
                  height: 22,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Opacity(
                    opacity: 0.5,
                    child: Text(
                      AppI18n.of(context).t('chat.disclaimer'),
                      textAlign: TextAlign.end,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        height: 1.3,
                        color: isLight ? Colors.black : ExodoColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
    final label = AppI18n.of(context).t('sources.title');

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
          backgroundColor: isLight ? Colors.white : ExodoColors.background,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppI18n.of(context).t('sources.consulted'),
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sources.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 16, color: Colors.white12),
                      itemBuilder: (ctx, idx) {
                        final s = sources[idx];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor:
                                circleColors[idx % circleColors.length],
                            child: Text(
                              _sourceInitials(s),
                              style: TextStyle(fontFamily: 'AnthropicSans', 
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          title: Text(
                            s.title.isNotEmpty ? s.title : s.url,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.black87 : Colors.white,
                            ),
                          ),
                          subtitle: s.url.isNotEmpty
                              ? Text(
                                  s.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: ExodoColors.amber,
                                  ),
                                )
                              : null,
                          trailing: s.url.isNotEmpty
                              ? Icon(
                                  Icons.open_in_new_rounded,
                                  size: 18,
                                  color: ExodoColors.amber,
                                )
                              : null,
                          onTap: s.url.isNotEmpty
                              ? () async {
                                  HapticFeedback.lightImpact();
                                  final uri = Uri.tryParse(s.url);
                                  if (uri != null && await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } else {
                                    Clipboard.setData(
                                      ClipboardData(text: s.url),
                                    );
                                  }
                                }
                              : null,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xFF252525),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isLight ? Colors.black12 : const Color(0xFF333336),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isLight
                    ? const Color(0xFF4A4A4A)
                    : const Color(0xFFA0A0A5),
              ),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (ctx) {
                final displaySources = sources.take(4).toList();
                return SizedBox(
                  height: 20,
                  width: (displaySources.length * 12.0) + 8.0,
                  child: Stack(
                    children: [
                      for (int i = 0; i < displaySources.length; i++)
                        Positioned(
                          left: i * 12.0,
                          child: Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: circleColors[i % circleColors.length],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isLight
                                    ? Colors.white
                                    : const Color(0xFF252525),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              _sourceInitials(displaySources[i]),
                              style: TextStyle(fontFamily: 'AnthropicSans', 
                                fontSize: 8.5,
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
  return t.length >= 2
      ? t.substring(0, 2).toUpperCase()
      : t.substring(0, 1).toUpperCase();
}

/// Barra de acciones al pie de cada respuesta del asistente:
/// Copy · Play · Like · Dislike · Share.
class _MessageActionBar extends StatelessWidget {
  final ChatMessage message;
  final String copyLabel;
  final String copiedLabel;
  final String likeLabel;
  final String dislikeLabel;
  final String shareLabel;
  final String playLabel;
  const _MessageActionBar({
    required this.message,
    required this.copyLabel,
    required this.copiedLabel,
    required this.likeLabel,
    required this.dislikeLabel,
    required this.shareLabel,
    required this.playLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final subText = isLight ? Colors.black54 : Colors.white60;

    void share() {
      HapticFeedback.lightImpact();
      final playStoreUrl =
          'https://play.google.com/store/apps/details?id=com.behavior.exodo';
      final shareText =
          '${message.content}\n\n${AppI18n.of(context).t('feedback.share_msg')}\n$playStoreUrl';
      // ignore: deprecated_member_use
      Share.share(shareText, subject: 'Éxodo AI');
    }

    void showFeedbackModal(bool isLike) {
      final ctrl = TextEditingController();
      final title = isLike
          ? AppI18n.of(context).t('feedback.title_pos')
          : AppI18n.of(context).t('feedback.title_neg');
      final hint = AppI18n.of(context).t('feedback.hint');

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isLight
              ? const Color(0xFFF5F2EB)
              : const Color(0xFF252525),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                isLike
                    ? Icons.thumb_up_alt_rounded
                    : Icons.thumb_down_alt_rounded,
                color: ExodoColors.amber,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'AnthropicSans',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isLight
                        ? const Color(0xFF191919)
                        : ExodoColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: TextField(
            controller: ctrl,
            maxLines: 4,
            minLines: 2,
            style: TextStyle(
              fontFamily: 'AnthropicSans',
              fontSize: 14,
              color: isLight
                  ? const Color(0xFF191919)
                  : ExodoColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontFamily: 'AnthropicSans',
                color: ExodoColors.textSecondary,
                fontSize: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: isLight
                    ? BorderSide.none
                    : const BorderSide(color: ExodoColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: isLight
                    ? BorderSide.none
                    : const BorderSide(color: ExodoColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: isLight
                    ? BorderSide.none
                    : const BorderSide(color: ExodoColors.amber),
              ),
              filled: true,
              fillColor: isLight ? Colors.white : const Color(0xFF191919),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                AppI18n.of(context).t('ctx.cancel'),
                style: const TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: ExodoColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                final feedbackText = ctrl.text.trim();
                Navigator.pop(ctx);
                // [Punto 37 aviso] Feedback directo a Supabase (sin mailto).
                final convId = context.read<AppState>().activeConversation?.id;
                await SupabaseService.submitFeedback(
                  isLike: isLike,
                  comment: feedbackText,
                  messageExcerpt: message.content,
                  conversationId: convId,
                );
                // Feedback enviado silenciosamente
              },
              child: Text(
                AppI18n.of(context).t('action.send'),
                style: const TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: ExodoColors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    void like() {
      HapticFeedback.mediumImpact();
      showFeedbackModal(true);
    }

    void dislike() {
      HapticFeedback.mediumImpact();
      showFeedbackModal(false);
    }

    return Wrap(
      spacing: 18,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _SmartCopyButton(
          textToCopy: message.content,
          color: subText,
          copyLabel: copyLabel,
          copiedLabel: copiedLabel,
        ),
        _ActionButton(
          assetPath: 'assets/images/like-1-svgrepo-com.png',
          tooltip: likeLabel,
          color: subText,
          onTap: like,
        ),
        _ActionButton(
          assetPath: 'assets/images/like-1-svgrepo-com.png',
          flipVertically: true,
          tooltip: dislikeLabel,
          color: subText,
          onTap: dislike,
        ),
        _ActionButton(
          assetPath: 'assets/images/share-svgrepo-com.png',
          tooltip: shareLabel,
          color: subText,
          onTap: share,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String? assetPath;
  final IconData? icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  final bool flipVertically;
  const _ActionButton({
    this.assetPath,
    this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.flipVertically = false,
  }) : assert(
          assetPath != null || icon != null,
          '_ActionButton requiere assetPath o icon',
        );

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
      childWidget = Icon(icon, size: 18, color: color);
    }
    if (flipVertically) {
      childWidget = Transform.flip(flipY: true, child: childWidget);
    }
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Tooltip(
        message: tooltip,
        child: Padding(padding: const EdgeInsets.all(4), child: childWidget),
      ),
    );
  }
}

Widget _buildAttachmentThumbnail(Attachment att) {
  if (att.bytes.isNotEmpty) {
    return Image.memory(
      att.bytes,
      fit: BoxFit.cover,
      height: 140,
    );
  }
  if (att.filePath.isNotEmpty) {
    final file = File(att.filePath);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        height: 140,
      );
    } else if (kDebugMode) {
      debugPrint('[MessageBubble] Thumbnail file not found on disk: ${att.filePath}');
    }
  }
  return _MissingAttachmentPlaceholder(
    fileName: att.fileName,
  );
}

Widget _buildAttachmentFullScreen(Attachment att) {
  if (att.bytes.isNotEmpty) {
    return Image.memory(att.bytes);
  }
  if (att.filePath.isNotEmpty) {
    final file = File(att.filePath);
    if (file.existsSync()) {
      return Image.file(file);
    } else if (kDebugMode) {
      debugPrint('[MessageBubble] Fullscreen file not found on disk: ${att.filePath}');
    }
  }
  return _MissingAttachmentPlaceholder(
    fileName: att.fileName,
  );
}

/// [Fix LG V60 #2] Placeholder que se muestra cuando un adjunto de imagen
/// está referenciado en el historial pero sus bytes o su archivo físico ya
/// no están disponibles (re-instalación, caché limpiada, etc.).
class _MissingAttachmentPlaceholder extends StatelessWidget {
  final String fileName;
  const _MissingAttachmentPlaceholder({required this.fileName});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      height: 140,
      width: 140,
      decoration: BoxDecoration(
        color: isLight ? Colors.black12 : Colors.white12,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLight ? Colors.black26 : Colors.white24,
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 28,
            color: isLight ? Colors.black54 : Colors.white54,
          ),
          const SizedBox(height: 6),
          Text(
            fileName.isEmpty ? 'Adjunto' : fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isLight ? Colors.black54 : Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartCopyButton extends StatefulWidget {
  final String textToCopy;
  final Color? color;
  final String copyLabel;
  final String copiedLabel;
  const _SmartCopyButton({
    required this.textToCopy,
    this.color,
    required this.copyLabel,
    required this.copiedLabel,
  });

  @override
  State<_SmartCopyButton> createState() => _SmartCopyButtonState();
}

class _SmartCopyButtonState extends State<_SmartCopyButton> {
  bool _copied = false;

  void _copy() {
    HapticFeedback.vibrate();
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: widget.textToCopy));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final col = widget.color ?? (Theme.of(context).brightness == Brightness.light ? Colors.black54 : Colors.white60);
    return InkResponse(
      onTap: _copy,
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: _copied
            ? const Icon(Icons.check_rounded, size: 18, color: Colors.green)
            : Image.asset(
                'assets/images/copy-2-svgrepo-com.png',
                width: 18,
                height: 18,
                color: col,
              ),
      ),
    );
  }
}



class _TableElementBuilder extends MarkdownElementBuilder {
  final bool isLight;
  _TableElementBuilder(this.isLight);

  @override
  bool visitElementBefore(md.Element element) {
    return false;
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    try {
      final rows = <List<Widget>>[];
      final isHeaderRow = <bool>[];
      int maxCols = 0;

      void extractRows(md.Node node) {
        if (node is! md.Element) return;
        if (node.tag == 'tr') {
          final cells = <Widget>[];
          final isHead = node.children?.any((c) => c is md.Element && c.tag == 'th') ?? false;
          for (final cellNode in node.children ?? []) {
            if (cellNode is md.Element && (cellNode.tag == 'th' || cellNode.tag == 'td')) {
              final isTh = cellNode.tag == 'th';
              final cellText = cellNode.textContent.trim();
              cells.add(
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    cellText,
                    style: TextStyle(
                      fontFamily: 'AnthropicSans',
                      fontSize: 13,
                      fontWeight: isTh ? FontWeight.w600 : FontWeight.normal,
                      color: isTh
                          ? (isLight ? const Color(0xFF191919) : const Color(0xFFF5F2EB))
                          : (isLight ? const Color(0xFF333333) : const Color(0xFFD1D1D6)),
                    ),
                  ),
                ),
              );
            }
          }
          if (cells.isNotEmpty) {
            if (cells.length > maxCols) maxCols = cells.length;
            rows.add(cells);
            isHeaderRow.add(isHead);
          }
        } else {
          for (final child in node.children ?? []) {
            extractRows(child);
          }
        }
      }

      extractRows(element);

      if (rows.isEmpty || maxCols == 0) return const SizedBox.shrink();

      // Row normalization: Every TableRow must have the exact same number of children.
      final tableRows = <TableRow>[];
      for (int i = 0; i < rows.length; i++) {
        final rowCells = rows[i];
        while (rowCells.length < maxCols) {
          rowCells.add(
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox.shrink(),
            ),
          );
        }
        final isHead = isHeaderRow[i];
        tableRows.add(
          TableRow(
            decoration: BoxDecoration(
              color: isHead
                  ? (isLight ? const Color(0x0A000000) : const Color(0x0FFFFFFF))
                  : Colors.transparent,
            ),
            children: rowCells,
          ),
        );
      }

      final borderColor = isLight
          ? const Color(0x1F000000)
          : const Color(0x14FFFFFF); // subtle 1px rgba(255,255,255,0.08)

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 1.0),
              ),
              clipBehavior: Clip.hardEdge,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder.symmetric(
                  inside: BorderSide(color: borderColor, width: 1.0),
                ),
                children: tableRows,
              ),
            ),
          ),
        ),
      );
    } catch (e, stack) {
      debugPrint('[TableElementBuilder] Layout error prevented: $e\n$stack');
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          element.textContent,
          style: const TextStyle(
            fontFamily: 'AnthropicSans',
            fontSize: 12,
            color: Color(0xFF8E8E93),
          ),
        ),
      );
    }
  }
}

class _PreElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  final bool isLight;
  final String copyLabel;
  final String copiedLabel;
  _PreElementBuilder(this.context, this.isLight, this.copyLabel, this.copiedLabel);

  @override
  bool visitElementBefore(md.Element element) {
    return false;
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    String language = 'ARTEFACTO / CÓDIGO';
    String code = element.textContent;
    if (element.children != null && element.children!.isNotEmpty) {
      final first = element.children!.first;
      if (first is md.Element && first.attributes['class'] != null) {
        final cls = first.attributes['class']!;
        if (cls.startsWith('language-')) {
          language = cls.substring(9).toUpperCase();
        } else {
          language = cls.toUpperCase();
        }
      }
    }
    return _InteractiveCodeBlock(
      code: code.trimRight(),
      language: language,
      isLight: isLight,
      copyLabel: copyLabel,
      copiedLabel: copiedLabel,
    );
  }
}

class _InteractiveCodeBlock extends StatefulWidget {
  final String code;
  final String language;
  final bool isLight;
  final String copyLabel;
  final String copiedLabel;
  const _InteractiveCodeBlock({
    required this.code,
    required this.language,
    required this.isLight,
    required this.copyLabel,
    required this.copiedLabel,
  });

  @override
  State<_InteractiveCodeBlock> createState() => _InteractiveCodeBlockState();
}

class _InteractiveCodeBlockState extends State<_InteractiveCodeBlock> {
  bool _copied = false;

  void _copy() {
    HapticFeedback.vibrate();
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = !widget.isLight;
    final bg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF4F2EB);
    final borderColor = isDark ? const Color(0xFF2E2E2E) : const Color(0x14000000);
    final textCol = isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919);
    final langCol = isDark ? const Color(0xFFD4A843) : const Color(0xFF996B00);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header permanente con indicador de lenguaje
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 80, 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: borderColor, width: 1.0)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.code_rounded,
                      size: 15,
                      color: langCol,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.language.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'AnthropicSans',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: langCol,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Contenido con scroll vertical + scroll horizontal unconstrained para evitar texto aplastado
              Container(
                constraints: const BoxConstraints(maxHeight: 450),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  padding: const EdgeInsets.all(14),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: IntrinsicWidth(
                      child: SelectableText(
                        widget.code,
                        style: TextStyle(
                          fontFamily: 'AnthropicSans',
                          fontSize: 13,
                          color: textCol,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Botón "Copiar" fijado permanentemente en la esquina superior derecha
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _copy,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _copied
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _copied ? Colors.green.withValues(alpha: 0.5) : Colors.white12,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 13,
                      color: _copied ? Colors.green : ExodoColors.textPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _copied ? widget.copiedLabel : widget.copyLabel,
                      style: TextStyle(
                        fontFamily: 'AnthropicSans',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _copied ? Colors.green : ExodoColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle inline Eco Mode notice (GPT style without intermediate modals).
class _EcoModeNotice extends StatelessWidget {
  final bool isLight;
  const _EcoModeNotice({required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          UpgradeModal.show(context);
        },
        behavior: HitTestBehavior.opaque,
        child: Text.rich(
          TextSpan(
            text: "You've reached your daily limit. Continuing in eco mode, resets at 00:00 AST. ",
            style: TextStyle(
              fontFamily: 'AnthropicSans',
              fontSize: 11,
              fontWeight: FontWeight.normal,
              color: ExodoColors.textSecondary,
              height: 1.35,
            ),
            children: [
              TextSpan(
                text: '[Upgrade]',
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ExodoColors.amber,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantContentWithArtifacts extends StatelessWidget {
  final ChatMessage message;
  final bool isLight;
  final String copyLabel;
  final String copiedLabel;

  const _AssistantContentWithArtifacts({
    required this.message,
    required this.isLight,
    required this.copyLabel,
    required this.copiedLabel,
  });

  static String _sanitizeMarkdown(String input) {
    if (input.trim().isEmpty) return '';
    var s = input;
    // 1. Purge HTML comments
    s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    // 2. Purge DOCTYPE, scripts, and styles
    s = s.replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<script[\s\S]*?<\/script>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<style[\s\S]*?<\/style>', caseSensitive: false), '');
    // 3. Purge raw HTML open/close/self-closing tags so flutter_markdown AST inline stack is 100% clean
    s = s.replaceAll(RegExp(r'<\/?([a-zA-Z0-9_-]+)(?:\s+[^>]*)?\/?>'), '');
    return s;
  }

  @override
  Widget build(BuildContext context) {
    try {
      final parser = ArtifactParser();
      final parseResult = parser.parse(
        messageId: message.id,
        conversationId: message.conversationId,
        content: message.content,
      );

      final allArtifacts = <String, Artifact>{
        for (final a in parseResult.artifacts) a.id: a,
        for (final t in parseResult.tables) t.artifact.id: t.artifact,
      };

      final artifactRegex = RegExp(r'<!-- artifact:(art-[a-zA-Z0-9_\-]+) -->');
      final segments = <Widget>[];
      int lastEnd = 0;

      for (final match in artifactRegex.allMatches(parseResult.cleanedMarkdown)) {
        if (match.start > lastEnd) {
          final text = parseResult.cleanedMarkdown.substring(lastEnd, match.start).trim();
          if (text.isNotEmpty) {
            segments.add(_buildMarkdown(context, text));
          }
        }
        final artId = match.group(1);
        final artifact = allArtifacts[artId];
        if (artifact != null) {
          segments.add(_SafeArtifactCard(artifact: artifact, isLight: isLight));
        }
        lastEnd = match.end;
      }

      if (lastEnd < parseResult.cleanedMarkdown.length) {
        final remaining = parseResult.cleanedMarkdown.substring(lastEnd).trim();
        if (remaining.isNotEmpty) {
          segments.add(_buildMarkdown(context, remaining));
        }
      }

      if (segments.isEmpty) {
        return _buildMarkdown(context, message.content);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: segments,
      );
    } catch (e, stack) {
      debugPrint('[AssistantContentWithArtifacts] Parsing error: $e\n$stack');
      return SelectableText(
        message.content,
        style: TextStyle(
          fontFamily: 'AnthropicSerif',
          fontSize: 15.5,
          color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
          height: 1.45,
        ),
      );
    }
  }

  Widget _buildMarkdown(BuildContext context, String rawContent) {
    final content = _sanitizeMarkdown(rawContent);
    if (content.trim().isEmpty) return const SizedBox.shrink();

    try {
      return MarkdownBody(
        data: content,
        onTapLink: (text, href, title) {
          if (href != null) {
            final uri = Uri.tryParse(href);
            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        builders: {
          'pre': _PreElementBuilder(context, isLight, copyLabel, copiedLabel),
          'table': _TableElementBuilder(isLight),
        },
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          blockSpacing: 12.0,
          blockquotePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          blockquoteDecoration: BoxDecoration(
            color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8),
                width: 4,
              ),
            ),
          ),
          blockquote: TextStyle(
            fontFamily: 'AnthropicSerif',
            fontSize: 14.5,
            color: isLight ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
            fontStyle: FontStyle.italic,
            height: 1.45,
          ),
          horizontalRuleDecoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isLight ? const Color(0x14000000) : const Color(0x14FFFFFF),
                width: 1.0,
              ),
            ),
          ),
          p: TextStyle(
            fontFamily: 'AnthropicSerif',
            fontSize: 15.5,
            color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
            height: 1.45,
          ),
          h1: TextStyle(
            fontFamily: 'AnthropicSerif',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
          ),
          h2: TextStyle(
            fontFamily: 'AnthropicSerif',
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
          ),
          h3: TextStyle(
            fontFamily: 'AnthropicSerif',
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
          ),
          listBullet: TextStyle(
            fontFamily: 'AnthropicSerif',
            fontSize: 15.5,
            color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
          ),
          code: TextStyle(
            fontFamily: 'AnthropicSans',
            backgroundColor: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
            color: isLight ? const Color(0xFF0F172A) : const Color(0xFF38BDF8),
            fontSize: 13.5,
          ),
          codeblockDecoration: const BoxDecoration(),
          codeblockPadding: EdgeInsets.zero,
        ),
      );
    } catch (e, stack) {
      debugPrint('[AssistantContentWithArtifacts] MarkdownBody error: $e\n$stack');
      return SelectableText(
        content,
        style: TextStyle(
          fontFamily: 'AnthropicSerif',
          fontSize: 15.5,
          color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
          height: 1.45,
        ),
      );
    }
  }
}

class _SafeArtifactCard extends StatelessWidget {
  final Artifact artifact;
  final bool isLight;

  const _SafeArtifactCard({
    required this.artifact,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return ArtifactCard(artifact: artifact);
    } catch (e, stack) {
      debugPrint('[SafeArtifactCard] Fallback error: $e\n$stack');
      final cardBg = isLight ? const Color(0xFFF4F2EB) : const Color(0xFF1E1E1E);
      final borderColor = isLight ? const Color(0x14000000) : const Color(0xFF2E2E2E);
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        child: SelectableText(
          artifact.sourceCode,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: isLight ? const Color(0xFF191919) : const Color(0xFFF5F2EB),
          ),
        ),
      );
    }
  }
}

