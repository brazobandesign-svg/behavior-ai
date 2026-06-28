import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/exodo_theme.dart';
import '../l10n/app_i18n.dart';

/// Bloque de código con botón "Copiar" en la esquina superior derecha.
///
/// Diseñado para reemplazar el render de code blocks de flutter_markdown,
/// agregando una acción clara de copiar que el componente base no provee.
///
/// Visualmente:
///   • Fondo oscuro tipo terminal (independiente del theme).
///   • Texto JetBrains Mono.
///   • Botón "Copiar" en la esquina superior derecha, solo aparece en hover/tap.
///   • Indicador de lenguaje ("dart", "js", etc.) si se especifica.
///
/// Nota: NO incluye syntax highlighting real (eso requiere flutter_highlight
/// u otro paquete). Si quieres colores de keywords, instala flutter_highlight
/// y reemplaza el `Text` interno por `HighlightView`.
class CodeBlockWidget extends StatefulWidget {
  final String code;
  final String? language;

  const CodeBlockWidget({
    super.key,
    required this.code,
    this.language,
  });

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    // Resetear el icono después de 2s.
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Fondo tipo "terminal" — siempre oscuro para que el código se lea bien
    // independientemente del theme de la app.
    final bgColor = const Color(0xFF131313);
    final borderColor = ExodoColors.border;
    final textColor = Colors.white;

    final i18n = AppI18n.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: lenguaje + botón copiar.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.code_rounded,
                      size: 13,
                      color: ExodoColors.amber.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      (widget.language ?? 'code').toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: ExodoColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _copy,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check_rounded : Icons.copy_rounded,
                            size: 13,
                            color: _copied ? ExodoColors.amber : ExodoColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copied
                                ? i18n.t('code.copied')
                                : i18n.t('code.copy'),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _copied ? ExodoColors.amber : ExodoColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Línea separadora sutil.
          Container(height: 1, color: borderColor, margin: const EdgeInsets.only(top: 8)),
          // Código.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: SelectableText(
              widget.code,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: textColor,
                height: 1.5,
              ),
            ),
          ),
          // Ajustar el contraste si el theme es claro para que se vea integrado.
          if (isLight)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}