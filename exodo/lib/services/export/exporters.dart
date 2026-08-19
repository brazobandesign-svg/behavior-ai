import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../data/artifacts/artifact.dart';
import '../../models/models.dart';
import '../../theme/exodo_palette.dart';
import '../../screens/artifacts/artifact_fullscreen.dart' show SandboxTemplate;

// ═══════════════════════════════════════════════════════════════════════════════
// 1. EXPORTER HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

class ExporterHelpers {
  ExporterHelpers._();

  /// Convierte Markdown a texto plano conservando estructura básica: headings
  /// en mayúsculas, listas con bullet, code blocks preservados.
  static String markdownToPlainText(String markdown) {
    if (markdown.isEmpty) return '';
    final lines = markdown.split('\n');
    final out = <String>[];
    bool inCode = false;
    for (final raw in lines) {
      final line = raw;
      final trimmed = line.trim();
      if (trimmed.startsWith('```')) {
        inCode = !inCode;
        out.add('');
        continue;
      }
      if (inCode) {
        out.add(line);
        continue;
      }
      if (line.startsWith('# ')) {
        out.add(line.substring(2).toUpperCase());
        out.add('');
      } else if (line.startsWith('## ')) {
        out.add(line.substring(3));
        out.add('');
      } else if (line.startsWith('### ')) {
        out.add('• ${line.substring(4)}');
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        out.add('• ${line.substring(2)}');
      } else if (RegExp(r'^\d+\.\s').hasMatch(line)) {
        out.add(line);
      } else {
        out.add(line);
      }
    }
    return out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// Escape de caracteres XML para docx/excel.
  static String escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Sanitiza un nombre de archivo (sin espacios, sin acentos peligrosos, sin
  /// caracteres de control).
  static String safeFilename(String s) {
    final cleaned = s
        .toLowerCase()
        .replaceAll(RegExp(r'[\s/\\:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return cleaned.isEmpty ? 'exodo' : cleaned;
  }

  /// Convierte un Color a hex de 6 caracteres (RRGGBB).
  static String colorToHex6(Color c) {
    return (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  /// Convierte un Color a ARGB hex de 8 caracteres (AARRGGBB).
  static String colorToArgbHex(Color c) {
    final v = c.toARGB32();
    return v.toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  /// Convierte un Color de Flutter a ARGB hex para Excel.
  static String colorToExcelArgbHex(Color c) => colorToArgbHex(c);
}

// ═══════════════════════════════════════════════════════════════════════════════
// 2. PDF EXPORTER
// ═══════════════════════════════════════════════════════════════════════════════

class PdfExporter {
  PdfExporter();

  /// Exporta un único artefacto como PDF. Devuelve el archivo temporal.
  Future<File> exportArtifact(Artifact artifact) async {
    final (regular, bold, mono, monoBold) = await _loadFonts();

    final doc = pw.Document(
      title: artifact.title ?? artifact.kind.name.toUpperCase(),
      author: 'Éxodo by Behavior',
      creator: 'Éxodo by Behavior',
      subject: 'Artefacto Éxodo',
    );

    final pageTheme = await _pageTheme(regular, bold, mono);

    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        header: (ctx) => _header(ctx),
        footer: (ctx) => _footer(ctx),
        build: (ctx) => [
          _coverBlock(
            title: artifact.title ?? artifact.kind.name.toUpperCase(),
            kindLabel: artifact.kind.name.toUpperCase(),
            mono: mono,
            bold: bold,
          ),
          pw.SizedBox(height: 24),
          ..._buildArtifact(artifact, regular, bold, mono, monoBold),
        ],
      ),
    );

    return _write(doc, _filename(artifact));
  }

  /// Exporta una conversación completa como PDF. Devuelve el archivo temporal.
  Future<File> exportConversation({
    required String conversationTitle,
    required List<ChatMessage> messages,
    required List<Artifact> artifacts,
  }) async {
    final (regular, bold, mono, monoBold) = await _loadFonts();

    final doc = pw.Document(
      title: conversationTitle,
      author: 'Éxodo by Behavior',
      creator: 'Éxodo by Behavior',
      subject: 'Conversación Éxodo',
    );

    final pageTheme = await _pageTheme(regular, bold, mono);

    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        header: (ctx) => _header(ctx),
        footer: (ctx) => _footer(ctx),
        build: (ctx) {
          final widgets = <pw.Widget>[
            _coverBlock(
              title: conversationTitle,
              kindLabel: 'CONVERSACIÓN',
              mono: mono,
              bold: bold,
              subtitle: '${messages.length} mensajes',
            ),
            pw.SizedBox(height: 24),
          ];
          for (final m in messages) {
            widgets.addAll(_buildMessage(m, regular, bold, mono));
            final arts = artifacts.where((a) => a.messageId == m.id);
            for (final a in arts) {
              widgets.add(pw.SizedBox(height: 6));
              widgets.addAll(_buildArtifact(a, regular, bold, mono, monoBold));
            }
            widgets.add(pw.SizedBox(height: 10));
          }
          return widgets;
        },
      ),
    );

    return _write(doc, _safeFilename('exodo-$conversationTitle.pdf'));
  }

  // ─── Theme + chrome ────────────────────────────────────────────────────

  Future<pw.PageTheme> _pageTheme(
      pw.Font regular, pw.Font bold, pw.Font mono) async {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 56,
        marginRight: 56,
        marginTop: 72,
        marginBottom: 64,
      ),
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        fontFallback: [mono],
      ),
    );
  }

  pw.Widget _header(pw.Context ctx) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'ÉXODO  by  Behavior',
            style: pw.TextStyle(
              font: pw.Font.courier(),
              fontSize: 8,
              color: PdfColor.fromInt(ExodoPalette.gold.toARGB32()),
              letterSpacing: 2,
            ),
          ),
          pw.Text(
            'p. ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColor.fromInt(ExodoPalette.textMuted.toARGB32()),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(pw.Context ctx) {
    final now = DateTime.now();
    final stamp = '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Text(
        'Éxodo by Behavior · IA con contexto dominicano · $stamp',
        style: pw.TextStyle(
          fontSize: 7.5,
          color: PdfColor.fromInt(ExodoPalette.textMuted.toARGB32()),
        ),
      ),
    );
  }

  // ─── Cover ────────────────────────────────────────────────────────────

  pw.Widget _coverBlock({
    required String title,
    required String kindLabel,
    required pw.Font mono,
    required pw.Font bold,
    String? subtitle,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(width: 60, height: 4, color: PdfColor.fromInt(ExodoPalette.gold.toARGB32())),
        pw.SizedBox(height: 22),
        pw.Text(
          'ÉXODO',
          style: pw.TextStyle(
            font: bold,
            fontSize: 10,
            letterSpacing: 6,
            color: PdfColor.fromInt(ExodoPalette.gold.toARGB32()),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'by Behavior · IA con contexto dominicano',
          style: pw.TextStyle(
            font: mono,
            fontSize: 8,
            color: PdfColor.fromInt(ExodoPalette.textMuted.toARGB32()),
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 24),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(ExodoPalette.gold.toARGB32()),
          ),
          child: pw.Text(
            kindLabel,
            style: pw.TextStyle(
              font: bold,
              fontSize: 8,
              letterSpacing: 2,
              color: PdfColor.fromInt(ExodoPalette.inkDeep.toARGB32()),
            ),
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          title,
          style: pw.TextStyle(
            font: bold,
            fontSize: 26,
            color: PdfColor.fromInt(ExodoPalette.inkDeep.toARGB32()),
            lineSpacing: 1.2,
          ),
        ),
        if (subtitle != null) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            subtitle,
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColor.fromInt(ExodoPalette.textMuted.toARGB32()),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Bloques de mensaje y artefacto ───────────────────────────────────

  List<pw.Widget> _buildMessage(ChatMessage m, pw.Font r, pw.Font b, pw.Font mono) {
    final isUser = m.role == 'user';
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: isUser
              ? PdfColor.fromInt(ExodoPalette.paper.toARGB32())
              : PdfColor.fromInt(ExodoPalette.paperSoft.toARGB32()),
          border: pw.Border.all(
            color: isUser
                ? PdfColor.fromInt(ExodoPalette.gold.toARGB32())
                : PdfColors.grey300,
            width: 0.8,
          ),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              isUser ? 'TÚ' : 'ÉXODO',
              style: pw.TextStyle(
                font: b,
                fontSize: 8.5,
                letterSpacing: 1.5,
                color: isUser
                    ? PdfColor.fromInt(ExodoPalette.goldDeep.toARGB32())
                    : PdfColor.fromInt(ExodoPalette.textMuted.toARGB32()),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              ExporterHelpers.markdownToPlainText(m.content),
              style: pw.TextStyle(
                font: r,
                fontSize: 10,
                color: PdfColor.fromInt(ExodoPalette.inkDeep.toARGB32()),
                lineSpacing: 1.3,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> _buildArtifact(
      Artifact a, pw.Font r, pw.Font b, pw.Font mono, pw.Font monoBold) {
    if (a.kind == ArtifactKind.table) {
      return _buildTableArtifact(a, b, r);
    }
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 6, bottom: 12),
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(ExodoPalette.inkRaised.toARGB32()),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: PdfColor.fromInt(ExodoPalette.inkLine.toARGB32())),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  (a.title ?? a.kind.name).toUpperCase(),
                  style: pw.TextStyle(
                    font: monoBold,
                    fontSize: 8.5,
                    color: PdfColor.fromInt(ExodoPalette.gold.toARGB32()),
                    letterSpacing: 1,
                  ),
                ),
                _kindBadge(a.kind, b),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              a.sourceCode,
              style: pw.TextStyle(
                font: mono,
                fontSize: 8,
                color: PdfColor.fromInt(ExodoPalette.textOnDark.toARGB32()),
                lineSpacing: 1.3,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> _buildTableArtifact(Artifact a, pw.Font b, pw.Font r) {
    final headers = _asStringList(a.meta['headers']);
    final rows = _asRowList(a.meta['rows']);

    if (headers.isEmpty && rows.isEmpty) {
      return [
        pw.Text(
          a.sourceCode,
          style: pw.TextStyle(font: pw.Font.courier(), fontSize: 8),
        ),
      ];
    }

    return [
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        headerStyle: pw.TextStyle(
          font: b,
          fontSize: 8.5,
          color: PdfColors.white,
          letterSpacing: 0.5,
        ),
        headerDecoration: pw.BoxDecoration(
          color: PdfColor.fromInt(ExodoPalette.gold.toARGB32()),
        ),
        cellStyle: pw.TextStyle(
          font: r,
          fontSize: 8,
          color: PdfColor.fromInt(ExodoPalette.inkDeep.toARGB32()),
        ),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
      ),
    ];
  }

  pw.Widget _kindBadge(ArtifactKind k, pw.Font b) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(ExodoPalette.gold.toARGB32()),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      child: pw.Text(
        k.name.toUpperCase(),
        style: pw.TextStyle(
          font: b,
          fontSize: 6.5,
          color: PdfColor.fromInt(ExodoPalette.inkDeep.toARGB32()),
          letterSpacing: 1,
        ),
      ),
    );
  }

  // ─── IO + fuentes ─────────────────────────────────────────────────────

  Future<(pw.Font, pw.Font, pw.Font, pw.Font)> _loadFonts() async {
    try {
      final regular = await _loadFont('assets/fonts/AnthropicSans-Text-Regular-Static.otf');
      final bold = await _loadFont('assets/fonts/AnthropicSans-Text-Bold-Static.otf');
      final mono = pw.Font.courier();
      final monoBold = pw.Font.courierBold();
      return (regular, bold, mono, monoBold);
    } catch (_) {
      try {
        final regular = await _loadFont('assets/fonts/AnthropicSans-Text-Regular.otf');
        final bold = await _loadFont('assets/fonts/AnthropicSans-Text-Bold.otf');
        final mono = pw.Font.courier();
        final monoBold = pw.Font.courierBold();
        return (regular, bold, mono, monoBold);
      } catch (_) {
        return (pw.Font.helvetica(), pw.Font.helveticaBold(), pw.Font.courier(), pw.Font.courierBold());
      }
    }
  }

  Future<pw.Font> _loadFont(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return pw.Font.ttf(data);
  }

  String _filename(Artifact a) {
    final base = a.title ?? a.kind.name;
    final tail = a.id.length >= 6 ? a.id.substring(a.id.length - 6) : a.id;
    return 'exodo-${ExporterHelpers.safeFilename(base)}-$tail.pdf';
  }

  String _safeFilename(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-_]'), '-').replaceAll(RegExp(r'-+'), '-');

  Future<File> _write(pw.Document doc, String filename) async {
    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes);
    return file;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  List<String> _asStringList(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList(growable: false);
    return const <String>[];
  }

  List<List<String>> _asRowList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<List>()
          .map((r) => r.map((c) => c.toString()).toList(growable: true))
          .toList(growable: false);
    }
    return const <List<String>>[];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3. DOCX EXPORTER (Pure OpenXML Builder)
// ═══════════════════════════════════════════════════════════════════════════════

class DocxExporter {
  DocxExporter();

  Future<File> exportArtifact(Artifact artifact) async {
    final sb = StringBuffer();
    final goldHex = ExporterHelpers.colorToHex6(ExodoPalette.gold);
    final darkHex = ExporterHelpers.colorToHex6(ExodoPalette.inkDeep);
    final mutedHex = ExporterHelpers.colorToHex6(ExodoPalette.textMuted);

    sb.writeln(_docxHeading(artifact.title ?? artifact.kind.name.toUpperCase(), level: 1, colorHex: darkHex, sizePt: 22));
    sb.writeln(_docxParagraph('Artefacto Éxodo · ${artifact.language} · ${_stamp()}', colorHex: mutedHex, italic: true, sizePt: 9.5));
    sb.writeln(_docxSpacer());

    if (artifact.kind == ArtifactKind.table) {
      sb.writeln(_docxTable(artifact, headerBgHex: goldHex));
    } else {
      sb.writeln(_docxCodeBlock(artifact.sourceCode));
    }

    final filename = 'exodo-${ExporterHelpers.safeFilename(artifact.title ?? artifact.kind.name)}-${_tail(artifact.id)}.docx';
    return _packageDocx(sb.toString(), filename);
  }

  Future<File> exportConversation({
    required String conversationTitle,
    required List<ChatMessage> messages,
    required List<Artifact> artifacts,
  }) async {
    final sb = StringBuffer();
    final goldHex = ExporterHelpers.colorToHex6(ExodoPalette.gold);
    final darkHex = ExporterHelpers.colorToHex6(ExodoPalette.inkDeep);
    final mutedHex = ExporterHelpers.colorToHex6(ExodoPalette.textMuted);

    sb.writeln(_docxHeading('ÉXODO', level: 0, colorHex: goldHex, sizePt: 16));
    sb.writeln(_docxHeading(conversationTitle, level: 1, colorHex: darkHex, sizePt: 24));
    sb.writeln(_docxParagraph('${messages.length} mensajes · ${_stamp()}', colorHex: mutedHex, italic: true, sizePt: 10));
    sb.writeln(_docxSpacer());

    var idx = 0;
    for (final m in messages) {
      idx++;
      final isUser = m.role == 'user';
      final speaker = isUser ? 'Tú (#$idx)' : 'Éxodo (#$idx)';
      sb.writeln(_docxHeading(speaker, level: 3, colorHex: isUser ? goldHex : darkHex, sizePt: 12));
      sb.writeln(_docxParagraph(ExporterHelpers.markdownToPlainText(m.content), sizePt: 10.5));

      for (final a in artifacts.where((x) => x.messageId == m.id)) {
        sb.writeln(_docxSpacer());
        sb.writeln(_docxHeading((a.title ?? a.kind.name).toUpperCase(), level: 3, colorHex: goldHex, sizePt: 11));
        if (a.kind == ArtifactKind.table) {
          sb.writeln(_docxTable(a, headerBgHex: goldHex));
        } else {
          sb.writeln(_docxCodeBlock(a.sourceCode));
        }
      }
      sb.writeln(_docxSpacer());
    }

    final filename = 'exodo-${ExporterHelpers.safeFilename(conversationTitle)}.docx';
    return _packageDocx(sb.toString(), filename);
  }

  // ─── XML Generation Helpers ──────────────────────────────────────────────

  String _docxHeading(String text, {required int level, required String colorHex, required double sizePt}) {
    final szVal = (sizePt * 2).round();
    final safeText = ExporterHelpers.escapeXml(text);
    return '''<w:p>
  <w:pPr>
    <w:pStyle w:val="Heading$level"/>
    <w:spacing w:before="180" w:after="80"/>
  </w:pPr>
  <w:r>
    <w:rPr>
      <w:b/>
      <w:color w:val="$colorHex"/>
      <w:sz w:val="$szVal"/>
      <w:szCs w:val="$szVal"/>
    </w:rPr>
    <w:t>$safeText</w:t>
  </w:r>
</w:p>''';
  }

  String _docxParagraph(String text, {String? colorHex, bool italic = false, double sizePt = 11}) {
    final szVal = (sizePt * 2).round();
    final safeText = ExporterHelpers.escapeXml(text);
    final colorXml = colorHex != null ? '<w:color w:val="$colorHex"/>' : '';
    final italicXml = italic ? '<w:i/><w:iCs/>' : '';

    return '''<w:p>
  <w:pPr>
    <w:spacing w:before="40" w:after="80" w:line="276" w:lineRule="auto"/>
  </w:pPr>
  <w:r>
    <w:rPr>
      $colorXml
      $italicXml
      <w:sz w:val="$szVal"/>
      <w:szCs w:val="$szVal"/>
    </w:rPr>
    <w:t xml:space="preserve">$safeText</w:t>
  </w:r>
</w:p>''';
  }

  String _docxSpacer() => '<w:p><w:pPr><w:spacing w:before="60" w:after="60"/></w:pPr></w:p>';

  String _docxCodeBlock(String source) {
    final buffer = StringBuffer();
    for (final raw in source.split('\n')) {
      final safeLine = ExporterHelpers.escapeXml(raw.isEmpty ? ' ' : raw);
      buffer.writeln('''<w:p>
  <w:pPr>
    <w:shd w:val="clear" w:color="auto" w:fill="F4F1EC"/>
    <w:spacing w:before="0" w:after="0" w:line="220" w:lineRule="auto"/>
    <w:ind w:left="140" w:right="140"/>
  </w:pPr>
  <w:r>
    <w:rPr>
      <w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>
      <w:sz w:val="19"/>
      <w:szCs w:val="19"/>
      <w:color w:val="0E0C0A"/>
    </w:rPr>
    <w:t xml:space="preserve">$safeLine</w:t>
  </w:r>
</w:p>''');
    }
    return buffer.toString();
  }

  String _docxTable(Artifact a, {required String headerBgHex}) {
    final headers = _asStringList(a.meta['headers']);
    final rows = _asRowList(a.meta['rows']);
    final buffer = StringBuffer();

    buffer.writeln('''<w:tbl>
  <w:tblPr>
    <w:tblW w:w="5000" w:type="pct"/>
    <w:tblBorders>
      <w:top w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
      <w:left w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
      <w:bottom w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
      <w:right w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
      <w:insideH w:val="single" w:sz="4" w:space="0" w:color="E2DDD5"/>
      <w:insideV w:val="single" w:sz="4" w:space="0" w:color="E2DDD5"/>
    </w:tblBorders>
  </w:tblPr>''');

    if (headers.isNotEmpty) {
      buffer.writeln('  <w:tr><w:trPr><w:tblHeader/></w:trPr>');
      for (final h in headers) {
        final safeH = ExporterHelpers.escapeXml(h.toUpperCase());
        buffer.writeln('''    <w:tc>
      <w:tcPr>
        <w:shd w:val="clear" w:color="auto" w:fill="$headerBgHex"/>
        <w:tcMar><w:top w:w="80"/><w:bottom w:w="80"/><w:left w:w="120"/><w:right w:w="120"/></w:tcMar>
      </w:tcPr>
      <w:p><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="19"/></w:rPr><w:t>$safeH</w:t></w:r></w:p>
    </w:tc>''');
      }
      buffer.writeln('  </w:tr>');
    }

    for (final row in rows) {
      buffer.writeln('  <w:tr>');
      for (final c in row) {
        final safeCell = ExporterHelpers.escapeXml(c);
        buffer.writeln('''    <w:tc>
      <w:tcPr>
        <w:tcMar><w:top w:w="60"/><w:bottom w:w="60"/><w:left w:w="100"/><w:right w:w="100"/></w:tcMar>
      </w:tcPr>
      <w:p><w:r><w:rPr><w:sz w:val="19"/><w:color w:val="1A1714"/></w:rPr><w:t>$safeCell</w:t></w:r></w:p>
    </w:tc>''');
      }
      buffer.writeln('  </w:tr>');
    }

    buffer.writeln('</w:tbl>');
    return buffer.toString();
  }

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

  String _stamp() {
    final d = DateTime.now();
    return '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
  String _tail(String id) => id.length >= 6 ? id.substring(id.length - 6) : id;

  List<String> _asStringList(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList(growable: false);
    return const <String>[];
  }

  List<List<String>> _asRowList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<List>()
          .map((r) => r.map((c) => c.toString()).toList(growable: true))
          .toList(growable: false);
    }
    return const <List<String>>[];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 4. XLSX EXPORTER
// ═══════════════════════════════════════════════════════════════════════════════

class XlsxExporter {
  XlsxExporter();

  /// Devuelve null si el artefacto no es tabular o no tiene datos estructurados.
  Future<File?> exportArtifact(Artifact artifact) async {
    if (artifact.kind != ArtifactKind.table && artifact.kind != ArtifactKind.json) {
      return null;
    }

    final headers = _asStringList(artifact.meta['headers']);
    final rows = _asRowList(artifact.meta['rows']);
    if (headers.isEmpty && rows.isEmpty) return null;

    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Datos');
    final sheet = excel['Datos'];

    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
      backgroundColorHex:
          ExcelColor.fromHexString(ExporterHelpers.colorToExcelArgbHex(ExodoPalette.gold)),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    // Cabecera
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }

    // Filas
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
        );
        cell.value = TextCellValue(rows[r][c]);
      }
    }

    // Auto-width aproximado
    for (var c = 0; c < headers.length; c++) {
      var maxLen = headers[c].length;
      for (final row in rows) {
        if (c < row.length && row[c].length > maxLen) maxLen = row[c].length;
      }
      final width = (maxLen * 1.2).clamp(10.0, 60.0);
      sheet.setColumnWidth(c, width);
    }

    final bytes = excel.encode();
    if (bytes == null) return null;

    final dir = await getTemporaryDirectory();
    final filename =
        'exodo-${ExporterHelpers.safeFilename(artifact.title ?? 'tabla')}-${_tail(artifact.id)}.xlsx';
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Variante explícita: genera XLSX a partir de un par (headers, rows).
  Future<File?> exportTable({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    if (headers.isEmpty && rows.isEmpty) return null;

    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Datos');
    final sheet = excel['Datos'];

    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
      backgroundColorHex:
          ExcelColor.fromHexString(ExporterHelpers.colorToExcelArgbHex(ExodoPalette.gold)),
    );

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
        );
        cell.value = TextCellValue(rows[r][c]);
      }
    }

    final bytes = excel.encode();
    if (bytes == null) return null;

    final dir = await getTemporaryDirectory();
    final filename = 'exodo-${ExporterHelpers.safeFilename(title)}.xlsx';
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes);
    return file;
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  List<String> _asStringList(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList(growable: false);
    return const <String>[];
  }

  List<List<String>> _asRowList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<List>()
          .map((r) => r.map((c) => c.toString()).toList(growable: true))
          .toList(growable: false);
    }
    return const <List<String>>[];
  }

  String _tail(String id) => id.length >= 6 ? id.substring(id.length - 6) : id;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 5. SHARE SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

class ShareService {
  ShareService._();
  static final ShareService instance = ShareService._();

  /// Comparte un archivo (PDF, DOCX, XLSX, HTML, etc.) usando el Share Sheet nativo.
  Future<ShareResult> shareFile(
    File file, {
    String? text,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: _guessMime(file.path))],
        text: text,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// Comparte texto plano (sin archivo adjunto).
  Future<ShareResult> shareText(
    String text, {
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    return SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  String _guessMime(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.pdf':
        return 'application/pdf';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.html':
      case '.htm':
        return 'text/html';
      case '.svg':
        return 'image/svg+xml';
      case '.md':
        return 'text/markdown';
      case '.json':
        return 'application/json';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 6. EXPORT RESULT
// ═══════════════════════════════════════════════════════════════════════════════

enum ExportFormat { pdf, docx, xlsx, html }

class ExportResult {
  final File file;
  final ExportFormat format;
  final String filename;
  final int sizeBytes;
  final String? title;

  const ExportResult({
    required this.file,
    required this.format,
    required this.filename,
    required this.sizeBytes,
    this.title,
  });

  String get mimeType {
    switch (format) {
      case ExportFormat.pdf:
        return 'application/pdf';
      case ExportFormat.docx:
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case ExportFormat.xlsx:
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case ExportFormat.html:
        return 'text/html';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 7. EXPORT REPOSITORY HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

class ExportRepositoryHelpers {
  ExportRepositoryHelpers._();

  static Future<File?> exportStandaloneHtml(Artifact artifact) async {
    final dir = await getTemporaryDirectory();
    final filename =
        'exodo-${ExporterHelpers.safeFilename(artifact.title ?? artifact.kind.name)}-${_tail(artifact.id)}.html';
    final file = File(p.join(dir.path, filename));
    final body = SandboxTemplate.wrap(kind: artifact.kind, source: artifact.sourceCode);
    await file.writeAsString(body);
    return file;
  }

  static Future<ExportResult?> exportArtifactAsPdf(Artifact a) =>
      _wrap(PdfExporter().exportArtifact(a), ExportFormat.pdf,
          title: a.title ?? a.kind.name);

  static Future<ExportResult?> exportArtifactAsDocx(Artifact a) =>
      _wrap(DocxExporter().exportArtifact(a), ExportFormat.docx,
          title: a.title ?? a.kind.name);

  static Future<ExportResult?> exportArtifactAsXlsx(Artifact a) =>
      _wrap(XlsxExporter().exportArtifact(a), ExportFormat.xlsx,
          title: a.title ?? a.kind.name);

  static Future<ExportResult> exportConversationAsPdf({
    required String title,
    required List<ChatMessage> messages,
    required List<Artifact> artifacts,
  }) async {
    final file = await PdfExporter().exportConversation(
      conversationTitle: title,
      messages: messages,
      artifacts: artifacts,
    );
    return ExportResult(
      file: file,
      format: ExportFormat.pdf,
      filename: p.basename(file.path),
      sizeBytes: await file.length(),
      title: title,
    );
  }

  static Future<ExportResult> exportConversationAsDocx({
    required String title,
    required List<ChatMessage> messages,
    required List<Artifact> artifacts,
  }) async {
    final file = await DocxExporter().exportConversation(
      conversationTitle: title,
      messages: messages,
      artifacts: artifacts,
    );
    return ExportResult(
      file: file,
      format: ExportFormat.docx,
      filename: p.basename(file.path),
      sizeBytes: await file.length(),
      title: title,
    );
  }

  static Future<ExportResult?> _wrap(
    Future<File?> future,
    ExportFormat fmt, {
    required String title,
  }) async {
    final file = await future;
    if (file == null) return null;
    return ExportResult(
      file: file,
      format: fmt,
      filename: p.basename(file.path),
      sizeBytes: await file.length(),
      title: title,
    );
  }

  static String _tail(String id) => id.length >= 6 ? id.substring(aId(id)) : id;
  static int aId(String id) => id.length >= 6 ? id.length - 6 : 0;
}
