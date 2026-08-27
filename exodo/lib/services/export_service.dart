// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT SERVICE (Markdown → Word / PDF)
// ─────────────────────────────────────────────────────────────────────────────
// Servicio de alto nivel que renderiza contenido Markdown de un Artefacto a
// archivos .docx y .pdf usando el parser puro `markdown_export_parser.dart`.
//
// Métodos públicos (dominio exclusivo de esta tarea):
//   * exportToDocx(String markdown, {String? title})
//   * exportToPdf(String markdown, {String? title})
//
// Ambos descomponen el contenido en bloques estructurados (headings, párrafos,
// código, listas) y aplican estilos tipográficos multinivel.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../theme/exodo_palette.dart';
import 'markdown_export_parser.dart';

/// Tupla con las fuentes cargadas para el render PDF.
typedef _PdfFonts = (pw.Font regular, pw.Font bold, pw.Font italic, pw.Font mono);

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  // ═══ DOCX ══════════════════════════════════════════════════════════════════

  /// Exporta el Markdown recibido a un archivo `.docx` usando el parser.
  /// Devuelve `null` en Web (no hay sistema de archivos).
  Future<File?> exportToDocx(String markdown, {String? title}) async {
    if (kIsWeb) return null;

    final blocks = MarkdownExportParser.parse(markdown);
    final titleText = (title == null || title.trim().isEmpty)
        ? 'ÉXODO'
        : title.trim();

    final sb = StringBuffer();
    sb.writeln(_docxHeading(0, [InlineSegment(text: titleText)]));
    sb.writeln('<w:p><w:pPr><w:spacing w:before="40" w:after="100"/></w:pPr></w:p>');

    for (final block in blocks) {
      sb.writeln(_renderDocxBlock(block));
    }

    final filename = 'exodo-${_safeFilename(titleText)}.docx';
    return _packageDocx(sb.toString(), filename);
  }

  String _renderDocxBlock(ExportBlock block) {
    switch (block.type) {
      case ExportBlockType.heading:
        return _docxHeading(block.level, block.inlines);
      case ExportBlockType.paragraph:
        return _docxParagraph(block.inlines);
      case ExportBlockType.bulletList:
        return _docxBulletList(block.items);
      case ExportBlockType.codeBlock:
        return _docxCodeBlock(block.codeLines);
    }
  }
// ─── DOCX: generación de XML ──────────────────────────────────────────────

  String _docxHeading(int level, List<InlineSegment> inlines) {
    // Nivel 0 (título de documento) cae a Heading1; 1..6 jerárquico.
    final styleLevel = level > 0 ? level.clamp(1, 6) : 1;
    final sizePt = switch (level) {
      5 => 12.0,
      4 => 12.5,
      3 => 14.0,
      2 => 16.0,
      _ => 20.0, // nivel 0, 1
    };
    final runs = inlines
        .map((s) => _inlineRun(s, sizePt: sizePt, colorHex: _darkHex, forceBold: true))
        .join();
    return '<w:p><w:pPr><w:pStyle w:val="Heading$styleLevel"/><w:spacing w:before="180" w:after="80"/></w:pPr>$runs</w:p>';
  }

  String _docxParagraph(List<InlineSegment> inlines) {
    final runs = inlines
        .map((s) => _inlineRun(s, sizePt: 10.5, colorHex: _darkHex))
        .join();
    return '<w:p><w:pPr><w:spacing w:before="40" w:after="80" w:line="276" w:lineRule="auto"/></w:pPr>$runs</w:p>';
  }

  String _docxBulletList(List<List<InlineSegment>> items) {
    final sb = StringBuffer();
    for (final item in items) {
      final runs = item
          .map((s) => _inlineRun(s, sizePt: 10.5, colorHex: _darkHex))
          .join();
      sb.writeln('<w:p><w:pPr><w:ind w:left="240" w:hanging="120"/>'
          '<w:spacing w:before="20" w:after="20"/></w:pPr>'
          '<w:r><w:rPr><w:b/><w:color w:val="$_goldHex"/><w:sz w:val="21"/>'
          '<w:szCs w:val="21"/></w:rPr><w:t xml:space="preserve">• </w:t></w:r>$runs</w:p>');
    }
    return sb.toString();
  }

  String _docxCodeBlock(List<String> lines) {
    final sb = StringBuffer();
    for (final raw in lines) {
      final safe = _escapeXml(raw.isEmpty ? ' ' : raw);
      sb.writeln('<w:p><w:pPr>'
          '<w:shd w:val="clear" w:color="auto" w:fill="F4F1EC"/>'
          '<w:spacing w:before="0" w:after="0" w:line="220" w:lineRule="auto"/>'
          '<w:ind w:left="140" w:right="140"/>'
          '</w:pPr>'
          '<w:r><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>'
          '<w:sz w:val="19"/><w:szCs w:val="19"/><w:color w:val="0E0C0A"/>'
          '</w:rPr><w:t xml:space="preserve">$safe</w:t></w:r></w:p>');
    }
    return sb.toString();
  }

  /// Genera un `<w:r>` (run) para un segmento inline, aplicando negrita,
  /// cursiva y fondo/letra mono para código inline.
  String _inlineRun(
    InlineSegment s, {
    required double sizePt,
    required String colorHex,
    bool forceBold = false,
  }) {
    final szVal = (sizePt * 2).round();
    final bold = s.bold || forceBold;
    final boldXml = bold ? '<w:b/><w:bCs/>' : '';
    final italXml = s.italic ? '<w:i/><w:iCs/>' : '';
    final fontXml = s.code
        ? '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>'
            '<w:shd w:val="clear" w:color="auto" w:fill="F4F1EC"/>'
        : '';
    final safeText = _escapeXml(s.text.isEmpty ? ' ' : s.text);
    return '<w:r><w:rPr>$fontXml$boldXml$italXml'
        '<w:color w:val="$colorHex"/><w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/>'
        '</w:rPr><w:t xml:space="preserve">$safeText</w:t></w:r>';
  }

  String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String _safeFilename(String s) {
    final cleaned = s
        .toLowerCase()
        .replaceAll(RegExp(r'[\s/\\:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return cleaned.isEmpty ? 'exodo' : cleaned;
  }

  static final String _goldHex = ExporterHexCache.gold;
  static final String _darkHex = ExporterHexCache.dark;

  Future<File> _packageDocx(String bodyXml, String filename) async {
    final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    $bodyXml
    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
    </w:sectPr>
  </w:body>
</w:document>''';

    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    final archive = Archive();
    final ctBytes = utf8.encode(contentTypesXml);
    final relsBytes = utf8.encode(rootRelsXml);
    final docBytes = utf8.encode(documentXml);
    archive.addFile(ArchiveFile('[Content_Types].xml', ctBytes.length, ctBytes));
    archive.addFile(ArchiveFile('_rels/.rels', relsBytes.length, relsBytes));
    archive.addFile(ArchiveFile('word/document.xml', docBytes.length, docBytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Error al comprimir archivo DOCX');
    }

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(zipBytes);
    return file;
  }
// ═══ PDF ══════════════════════════════════════════════════════════════════

  /// Exporta el Markdown recibido a un archivo `.pdf` usando el parser.
  /// Devuelve `null` en Web (no hay sistema de archivos).
  Future<File?> exportToPdf(String markdown, {String? title}) async {
    if (kIsWeb) return null;

    final blocks = MarkdownExportParser.parse(markdown);
    final titleText = (title == null || title.trim().isEmpty)
        ? 'ÉXODO'
        : title.trim();
    final fonts = await _loadFonts();

    final doc = pw.Document(
      title: titleText,
      author: 'Éxodo by Behavior',
      creator: 'Éxodo by Behavior',
      subject: 'Documento Éxodo',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 56,
          marginRight: 56,
          marginTop: 72,
          marginBottom: 64,
        ),
        build: (ctx) {
          final widgets = <pw.Widget>[
            pw.Text(
              titleText,
              style: pw.TextStyle(
                font: fonts.$2,
                fontSize: 20,
                color: PdfColor.fromInt(ExodoPalette.inkDeep.toARGB32()),
              ),
            ),
            pw.Container(
              width: 60,
              height: 3,
              color: PdfColor.fromInt(ExodoPalette.gold.toARGB32()),
            ),
            pw.SizedBox(height: 12),
          ];
          for (final block in blocks) {
            widgets.addAll(_pdfBlock(block, fonts));
          }
          return [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: widgets,
            ),
          ];
        },
      ),
    );

    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final filename = 'exodo-${_safeFilename(titleText)}.pdf';
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes);
    return file;
  }
List<pw.Widget> _pdfBlock(ExportBlock block, _PdfFonts fonts) {
    switch (block.type) {
      case ExportBlockType.heading:
        final size = switch (block.level) {
          5 => 12.0,
          4 => 12.5,
          3 => 14.0,
          2 => 16.0,
          _ => 19.0,
        };
        return [
          pw.SizedBox(height: 6),
          pw.Text(
            block.plainText,
            style: pw.TextStyle(
              font: fonts.$2,
              fontSize: size,
              color: PdfColor.fromInt(ExodoPalette.inkDeep.toARGB32()),
              lineSpacing: 1.15,
            ),
          ),
          pw.SizedBox(height: 4),
        ];

      case ExportBlockType.paragraph:
        return [
          pw.RichText(
            text: pw.TextSpan(
              children: _pdfSpans(block.inlines, fonts, size: 10.5),
            ),
            softWrap: true,
          ),
          pw.SizedBox(height: 8),
        ];

      case ExportBlockType.bulletList:
        final items = <pw.Widget>[];
        for (final item in block.items) {
          items.add(
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 4, top: 1),
                  child: pw.Text(
                    '•',
                    style: pw.TextStyle(
                      font: fonts.$2,
                      fontSize: 11,
                      color: PdfColor.fromInt(ExodoPalette.gold.toARGB32()),
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.RichText(
                    text: pw.TextSpan(
                      children: _pdfSpans(item, fonts, size: 10.5),
                    ),
                    softWrap: true,
                  ),
                ),
              ],
            ),
          );
          items.add(pw.SizedBox(height: 6));
        }
        items.add(pw.SizedBox(height: 4));
        return items;

      case ExportBlockType.codeBlock:
        final codeBg = PdfColor.fromInt(0xFFF4F1EC);
        final lineWidgets = <pw.Widget>[
          for (final line in block.codeLines)
            pw.Text(
              line.isEmpty ? ' ' : line,
              style: pw.TextStyle(
                font: fonts.$4,
                fontSize: 8,
                color: PdfColor.fromInt(ExodoPalette.inkDeep.toARGB32()),
                lineSpacing: 1.3,
              ),
            ),
        ];
        return [
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: codeBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: lineWidgets,
            ),
          ),
          pw.SizedBox(height: 8),
        ];
    }
  }

  /// Construye los TextSpan para un párrafo con negrita/cursiva/código.
  List<pw.TextSpan> _pdfSpans(
    List<InlineSegment> segs,
    _PdfFonts fonts, {
    double size = 10.5,
  }) {
    return [
      for (final seg in segs)
        pw.TextSpan(
          text: seg.text,
          style: pw.TextStyle(
            font: seg.code
                ? fonts.$4
                : seg.bold
                    ? fonts.$2
                    : seg.italic
                        ? fonts.$3
                        : fonts.$1,
            fontSize: size,
            fontStyle: seg.italic ? pw.FontStyle.italic : pw.FontStyle.normal,
            color: PdfColor.fromInt(
              (seg.code ? ExodoPalette.textMuted : ExodoPalette.inkDeep)
                  .toARGB32(),
            ),
            lineSpacing: 1.3,
          ),
        ),
    ];
  }

  Future<_PdfFonts> _loadFonts() async {
    try {
      final regular =
          await _loadFont('assets/fonts/AnthropicSans-Text-Regular-Static.otf');
      final bold =
          await _loadFont('assets/fonts/AnthropicSans-Text-Bold-Static.otf');
      final italic = await _loadFont(
          'assets/fonts/AnthropicSans-Text-RegularItalic-Static.otf');
      return (
        regular,
        bold,
        italic,
        pw.Font.courier(),
      );
    } catch (_) {
      return (
        pw.Font.helvetica(),
        pw.Font.helveticaBold(),
        pw.Font.helvetica(),
        pw.Font.courier(),
      );
    }
  }

  Future<pw.Font> _loadFont(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return pw.Font.ttf(data);
  }
}

/// Cache de colores de la paleta a hex (RRGGBB) para el XML de Word.
class ExporterHexCache {
  ExporterHexCache._();

  static final String gold = _hex6(ExodoPalette.gold.toARGB32());
  static final String dark = _hex6(ExodoPalette.inkDeep.toARGB32());

  static String _hex6(int argb) =>
      (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
}