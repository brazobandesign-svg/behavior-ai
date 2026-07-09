import 'dart:io';
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
                                    child: att.bytes.isNotEmpty
                                        ? Image.memory(att.bytes)
                                        : (att.filePath.isNotEmpty
                                            ? Image.file(File(att.filePath))
                                            : const SizedBox.shrink()),
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
                        child: att.bytes.isNotEmpty
                            ? Image.memory(
                                att.bytes,
                                fit: BoxFit.cover,
                                height: 140,
                              )
                            : (att.filePath.isNotEmpty
                                ? Image.file(
                                    File(att.filePath),
                                    fit: BoxFit.cover,
                                    height: 140,
                                  )
                                : const SizedBox.shrink()),
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
            if (message.content.isNotEmpty)
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.82,
                ),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: isLight
                      ? const Color(0xFFE8E8E8)
                      : const Color(0xFF131313),
                  borderRadius: BorderRadius.circular(20),
                  border: isLight
                      ? Border.all(color: const Color(0xFFDDDDDD), width: 1.0)
                      : null,
                ),
                child: MarkdownBody(
                  data: message.content,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                      .copyWith(
                        p: GoogleFonts.inter(
                          fontSize: 15,
                          color: isLight ? const Color(0xFF171615) : Colors.white,
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
            builders: {
              'pre': _PreElementBuilder(context, isLight),
            },
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  p: GoogleFonts.inter(
                    fontSize: 15.5,
                    color: isLight
                        ? const Color(0xFF171615)
                        : ExodoColors.textPrimary,
                    height: 1.45,
                  ),
                  code: GoogleFonts.jetBrainsMono(
                    backgroundColor: isLight
                        ? const Color(0xFFF5F5F5)
                        : ExodoColors.surface,
                    color: isLight
                        ? const Color(0xFFB85A35)
                        : ExodoColors.amber,
                  ),
                  codeblockDecoration: const BoxDecoration(),
                  codeblockPadding: EdgeInsets.zero,
                ),
          ),
          if (message.intentDetected != null) ...[
            const SizedBox(height: 8),
            Text(
              '${AppI18n.of(context).t('chat.intent')}: ${message.intentDetected}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: ExodoColors.amber.withValues(alpha: 0.8),
              ),
            ),
          ],
          if (message.sources.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SourcesSheet(sources: message.sources),
          ],
          const SizedBox(height: 10),
          _MessageActionBar(message: message),
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
                        color: isLight ? Colors.black : Colors.white,
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
          backgroundColor: isLight ? Colors.white : const Color(0xFF131313),
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
                              style: GoogleFonts.jetBrainsMono(
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
          color: isLight ? const Color(0xFFEAE7DF) : const Color(0xFF222224),
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
                                    ? const Color(0xFFEAE7DF)
                                    : const Color(0xFF222224),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              _sourceInitials(displaySources[i]),
                              style: GoogleFonts.jetBrainsMono(
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
/// Copy · Share · Like · Dislike.
class _MessageActionBar extends StatelessWidget {
  final ChatMessage message;
  const _MessageActionBar({required this.message});

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
              : ExodoColors.background,
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
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isLight
                        ? const Color(0xFF171615)
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
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isLight
                  ? const Color(0xFF171615)
                  : ExodoColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                color: ExodoColors.textSecondary,
                fontSize: 13,
              ),
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
                AppI18n.of(context).t('ctx.cancel'),
                style: GoogleFonts.inter(color: ExodoColors.textSecondary),
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
        ),
        _ActionButton(
          assetPath: 'assets/images/like-1-svgrepo-com.png',
          tooltip: AppI18n.of(context).t('act.like'),
          color: subText,
          onTap: like,
        ),
        _ActionButton(
          assetPath: 'assets/images/like-1-svgrepo-com.png',
          flipVertically: true,
          tooltip: AppI18n.of(context).t('act.dislike'),
          color: subText,
          onTap: dislike,
        ),
        _ActionButton(
          assetPath: 'assets/images/share-svgrepo-com.png',
          tooltip: AppI18n.of(context).t('act.share'),
          color: subText,
          onTap: share,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String? assetPath;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  final bool flipVertically;
  const _ActionButton({
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
      childWidget = Icon(Icons.circle, size: 18, color: color);
    }
    if (flipVertically) {
      childWidget = Transform.flip(flipY: true, child: childWidget);
    }
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(padding: const EdgeInsets.all(4), child: childWidget),
      ),
    );
  }
}

class _SmartCopyButton extends StatefulWidget {
  final String textToCopy;
  final Color? color;
  const _SmartCopyButton({required this.textToCopy, this.color});

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
    return Tooltip(
      message: _copied ? AppI18n.of(context).t('act.copied') : AppI18n.of(context).t('act.copy'),
      child: InkResponse(
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
      ),
    );
  }
}



class _PreElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  final bool isLight;
  _PreElementBuilder(this.context, this.isLight);

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
    );
  }
}

class _InteractiveCodeBlock extends StatefulWidget {
  final String code;
  final String language;
  final bool isLight;
  const _InteractiveCodeBlock({
    required this.code,
    required this.language,
    required this.isLight,
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
    final bg = widget.isLight ? const Color(0xFFF5F5F5) : ExodoColors.surface;
    final headerBg = widget.isLight ? const Color(0xFFE8E8E8) : const Color(0xFF1A1A1A);
    final borderCol = widget.isLight ? const Color(0xFFDDDDDD) : ExodoColors.border;
    final textCol = widget.isLight ? const Color(0xFFB85A35) : ExodoColors.amber;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header FIJO y PERMANENTE para el Artefacto (visible siempre al tope del bloque)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: headerBg,
            child: Row(
              children: [
                Icon(
                  Icons.code_rounded,
                  size: 16,
                  color: textCol,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.language,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textCol,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _copy,
                  behavior: HitTestBehavior.opaque,
                  child: Tooltip(
                    message: _copied
                        ? AppI18n.of(context).t('act.copied')
                        : AppI18n.of(context).t('act.copy'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: _copied
                            ? Colors.green.withValues(alpha: 0.15)
                            : widget.isLight
                                ? Colors.black.withValues(alpha: 0.05)
                                : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 14,
                        color: _copied ? Colors.green : (widget.isLight ? Colors.black87 : ExodoColors.textPrimary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Contenido del artefacto con altura máxima y scroll propio para mantener el botón SIEMPRE en pantalla
          Container(
            constraints: const BoxConstraints(maxHeight: 450),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                widget.code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: widget.isLight ? const Color(0xFF171615) : ExodoColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
