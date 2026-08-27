// ═══════════════════════════════════════════════════════════════════════════════
// MARKDOWN EXPORT PARSER
// ─────────────────────────────────────────────────────────────────────────────
// Parser puro y aislado (sin dependencias de Flutter/UI) que descompone el
// contenido Markdown de un Artefacto en bloques estructurados con estilos
// tipográficos, listos para ser renderizados por los exportadores de Word
// (DOCX) y PDF.
//
// Responsabilidades:
//   * Títulos  (#, ##, ###)  → bloques heading con nivel jerárquico (1..6).
//   * Negrita (**x** / __x__), cursiva (*x* / _x_) y código inline (`x`).
//   * Bloques de código (```lang …```) separados, con su lenguaje.
//   * Listas con viñetas (- / * / +).
//
// No toca UI ni traducciones; solo produce estructura. 100% null-safe.
// ═══════════════════════════════════════════════════════════════════════════════

/// Tipo de bloque de exportación detectado por el parser.
enum ExportBlockType {
  heading,
  paragraph,
  bulletList,
  codeBlock,
}

/// Un segmento de texto con estilo tipográfico inline (negrita, cursiva,
/// código). El texto ya viene "limpio" (sin los marcadores `**`, `*`, `` ` ``).
class InlineSegment {
  final String text;
  final bool bold;
  final bool italic;
  final bool code;

  const InlineSegment({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.code = false,
  });

  @override
  String toString() =>
      'InlineSegment($text, bold: $bold, italic: $italic, code: $code)';
}

/// Bloque estructurado de Markdown listo para exportar.
///
/// Dependiendo de [type] se usan unos campos u otros:
/// - [ExportBlockType.heading]: [level] + [inlines].
/// - [ExportBlockType.paragraph]: [inlines].
/// - [ExportBlockType.bulletList]: [items] (cada item = lista inline).
/// - [ExportBlockType.codeBlock]: [language] + [codeLines].
class ExportBlock {
  final ExportBlockType type;

  /// Nivel jerárquico del heading (1 = `#`, 2 = `##`, 3 = `###`, …).
  final int level;

  /// Lenguaje declarado tras la apertura del fence (p. ej. `dart`).
  final String? language;

  /// Líneas del bloque de código (sin los marcadores ```).
  final List<String> codeLines;

  /// Segmentos inline de un título, párrafo o item individual.
  final List<InlineSegment> inlines;

  /// Items de una lista con viñetas; cada item es su propia lista de inline.
  final List<List<InlineSegment>> items;

  const ExportBlock({
    required this.type,
    this.level = 0,
    this.language,
    this.codeLines = const [],
    this.inlines = const [],
    this.items = const [],
  });

  /// Conveniente: el texto plano concatenado de [inlines].
  String get plainText =>
      inlines.map((s) => s.text).join('');

  @override
  String toString() {
    switch (type) {
      case ExportBlockType.heading:
        return 'heading(${'#' * level}) ${inlines.map((s) => s.text).join()}';
      case ExportBlockType.paragraph:
        return 'paragraph ${inlines.map((s) => s.text).join()}';
      case ExportBlockType.bulletList:
        return 'bulletList(${items.length} items)';
      case ExportBlockType.codeBlock:
        return 'codeBlock(${language ?? ''}) ${codeLines.length} lines';
    }
  }
}
/// Parser puro de Markdown a bloques estructurados para exportación.
///
/// Uso:
/// ```dart
/// final blocks = MarkdownExportParser.parse(markdownSource);
/// ```
/// Clase estática sin estado ni dependencias externas.
class MarkdownExportParser {
  MarkdownExportParser._();

  // ─── Regex helpers ─────────────────────────────────────────────────────────
  static final RegExp _fenceStart = RegExp(r'^```+([^\s`]*)');
  static final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final RegExp _bullet = RegExp(r'^\s*([-*+])\s+(.*)$');

  /// Normaliza finales de línea (Windows/Mac) a `\n`.
  static String normalizeLineEndings(String content) =>
      content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  /// Descompone el Markdown recibido en una lista de [ExportBlock].
  ///
  /// - Títulos `#`/`##`/`###` → heading con nivel jerárquico.
  /// - Párrafos → paragraph con estilos inline (**negrita**, *cursiva*,
  ///   `código`).
  /// - Triple backtick (``` … ```) → codeBlock (sin interpretar inner).
  /// - Líneas `- `, `* `, `+ ` → bulletList (items agrupados consecutivos).
  static List<ExportBlock> parse(String content) {
    final normalized = normalizeLineEndings(content);
    if (normalized.trim().isEmpty) return const [];

    final lines = normalized.split('\n');
    final blocks = <ExportBlock>[];
    var i = 0;

    while (i < lines.length) {
      final raw = lines[i];
      final trimmed = raw.trim();

      // 1) Fence de código (abre un block).
      final fenceMatch = _fenceStart.firstMatch(trimmed);
      if (fenceMatch != null) {
        final language = fenceMatch.group(1)!.trim();
        i++;
        final codeLines = <String>[];
        // Recolecta hasta la línea de cierre ``` (o fin del texto).
        while (i < lines.length) {
          if (lines[i].trim().startsWith('```')) {
            i++;
            break;
          }
          codeLines.add(lines[i]);
          i++;
        }
        blocks.add(
          ExportBlock(
            type: ExportBlockType.codeBlock,
            language: language.isEmpty ? null : language,
            codeLines: codeLines,
          ),
        );
        continue;
      }

      // Línea vacía → salta.
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // 2) Título (heading).
      final headingMatch = _heading.firstMatch(trimmed);
      if (headingMatch != null) {
        blocks.add(
          ExportBlock(
            type: ExportBlockType.heading,
            level: headingMatch.group(1)!.length,
            inlines: parseInlines(headingMatch.group(2)!),
          ),
        );
        i++;
        continue;
      }
// 3) Lista de viñetas (agrupa items consecutivos).
      final bulletMatch = _bullet.firstMatch(trimmed);
      if (bulletMatch != null) {
        final items = <List<InlineSegment>>[
          parseInlines(bulletMatch.group(2)!),
        ];
        i++;
        while (i < lines.length) {
          final itemRaw = lines[i].trim();
          if (itemRaw.isEmpty) break;
          final itemMatch = _bullet.firstMatch(itemRaw);
          if (itemMatch == null) break;
          items.add(parseInlines(itemMatch.group(2)!));
          i++;
        }
        blocks.add(
          ExportBlock(type: ExportBlockType.bulletList, items: items),
        );
        continue;
      }

      // 4) Párrafo: agrupa líneas consecutivas no vacías ni especiales.
      final paragraphLines = <String>[];
      while (i < lines.length) {
        final pRaw = lines[i].trim();
        if (pRaw.isEmpty) break;
        if (_fenceStart.hasMatch(pRaw) ||
            _heading.hasMatch(pRaw) ||
            _bullet.hasMatch(pRaw)) {
          break;
        }
        paragraphLines.add(pRaw);
        i++;
      }
      final paragraph = paragraphLines.join(' ');
      if (paragraph.isNotEmpty) {
        blocks.add(
          ExportBlock(
            type: ExportBlockType.paragraph,
            inlines: parseInlines(paragraph),
          ),
        );
      }
    }

    return blocks;
  }

  /// Interpreta los marcadores inline de una cadena de texto:
  /// - `**negrita**` / `__negrita__`
  /// - `*cursiva*` / `_cursiva_`
  /// - `` `código` ``
  ///
  /// Retorna una lista de [InlineSegment] cuyo texto ya no contiene los
  /// marcadores. Se respeta el estado de apertura/cierre para permitir
  /// combinaciones como `**negrita y *cursiva***`.
  static List<InlineSegment> parseInlines(String text) {
    if (text.isEmpty) return const [];

    final out = <InlineSegment>[];
    final buffer = StringBuffer();
    var bold = false;
    var italic = false;
    var code = false;

    // Termina el segmento actual conservando los estilos activos.
    void flush() {
      if (buffer.isEmpty) return;
      final segmentText = buffer.toString();
      buffer.clear();
      out.add(InlineSegment(
        text: segmentText,
        bold: bold,
        italic: italic,
        code: code,
      ));
    }

    var i = 0;
    while (i < text.length) {
      final ch = text[i];

      // Código inline: captura verbatim hasta el backtick de cierre.
      if (code) {
        if (ch == '`') {
          flush();
          code = false;
          i++;
          continue;
        }
        buffer.write(ch);
        i++;
        continue;
      }

      if (ch == '`') {
        flush();
        code = true;
        i++;
        continue;
      }

      // Negrita / cursiva con `*`.
      if (ch == '*') {
        if (i + 1 < text.length && text[i + 1] == '*') {
          flush();
          bold = !bold;
          i += 2;
          continue;
        }
        flush();
        italic = !italic;
        i++;
        continue;
      }

      // Negrita / cursiva con guion bajo.
      if (ch == '_') {
        if (i + 1 < text.length && text[i + 1] == '_') {
          flush();
          bold = !bold;
          i += 2;
          continue;
        }
        // `_` entre palabras suele ser literal (foo_bar); solo se toggla
        // como cursiva si NO está rodeado de letras.
        final prevIsLetter = i > 0 && _isWordChar(text[i - 1]);
        final nextIsLetter =
            i + 1 < text.length && _isWordChar(text[i + 1]);
        if (prevIsLetter || nextIsLetter) {
          buffer.write('_');
          i++;
          continue;
        }
        flush();
        italic = !italic;
        i++;
        continue;
      }

      buffer.write(ch);
      i++;
    }
    flush();

    return out;
  }

  static bool _isWordChar(String c) {
    if (c.isEmpty) return false;
    final code = c.codeUnitAt(0);
    return (code >= 48 && code <= 57) || // 0-9
        (code >= 65 && code <= 90) || // A-Z
        (code >= 97 && code <= 122); // a-z
  }
}