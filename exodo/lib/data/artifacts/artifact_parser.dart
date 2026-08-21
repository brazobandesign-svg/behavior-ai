import 'artifact.dart';

class ArtifactTable {
  final Artifact artifact;
  final List<String?> alignments;
  final List<String> headers;
  final List<List<String>> rows;

  const ArtifactTable({
    required this.artifact,
    required this.alignments,
    required this.headers,
    required this.rows,
  });
}

class ArtifactParseResult {
  final String cleanedMarkdown;
  final List<Artifact> artifacts;
  final List<ArtifactTable> tables;

  const ArtifactParseResult({
    required this.cleanedMarkdown,
    required this.artifacts,
    this.tables = const [],
  });
}

class ArtifactParser {
  static final RegExp _fenceStart = RegExp(
    r'^(`{3,}|~{3,})\s*([a-zA-Z0-9_+-]*)\s*$',
    multiLine: true,
  );

  static final RegExp _artifactTag = RegExp(
    r'<artifact\s+([^>]*?)>([\s\S]*?)<\/artifact>',
    caseSensitive: false,
  );

  static const Map<String, ArtifactKind> _kindByLanguage = {
    'html': ArtifactKind.html,
    'htm': ArtifactKind.html,
    'svg': ArtifactKind.svg,
    'mermaid': ArtifactKind.mermaid,
    'jsx': ArtifactKind.react,
    'tsx': ArtifactKind.react,
    'vue': ArtifactKind.vue,
    'latex': ArtifactKind.latex,
    'tex': ArtifactKind.latex,
    'dart': ArtifactKind.code,
    'python': ArtifactKind.code,
    'py': ArtifactKind.code,
    'sql': ArtifactKind.code,
    'json': ArtifactKind.json,
    'javascript': ArtifactKind.code,
    'js': ArtifactKind.code,
    'typescript': ArtifactKind.code,
    'ts': ArtifactKind.code,
    'css': ArtifactKind.code,
    'yaml': ArtifactKind.code,
    'yml': ArtifactKind.code,
    'bash': ArtifactKind.code,
    'sh': ArtifactKind.code,
  };

  ArtifactParseResult parse({
    required String messageId,
    required String conversationId,
    required String content,
  }) {
    final artifacts = <Artifact>[];
    final tables = <ArtifactTable>[];

    // 1) Extraer tags <artifact ...>...</artifact> si existen
    var processed = _extractArtifactTags(
      content: content,
      messageId: messageId,
      conversationId: conversationId,
      artifactsSink: artifacts,
    );

    // 2) Extraer fenced code blocks (HTML, SVG, Mermaid, code, etc.)
    processed = _extractFences(
      content: processed,
      messageId: messageId,
      conversationId: conversationId,
      artifactsSink: artifacts,
    );

    // 3) Extraer HTML crudo o documentos completos sin fences
    processed = _extractRawHtml(
      content: processed,
      messageId: messageId,
      conversationId: conversationId,
      artifactsSink: artifacts,
    );

    return ArtifactParseResult(
      cleanedMarkdown: processed,
      artifacts: artifacts,
      tables: tables,
    );
  }

  /// Cleans markdown code fences, backticks, and HTML entities from extracted code.
  static String cleanCode(String raw) {
    if (raw.trim().isEmpty) return '';
    var s = raw.trim();

    // 1. Unescape HTML entities if detected in document tags
    if (s.startsWith('&lt;') ||
        s.contains('&lt;!DOCTYPE') ||
        s.contains('&lt;html') ||
        s.contains('&lt;div') ||
        s.contains('&lt;svg') ||
        s.contains('&lt;script') ||
        s.contains('&lt;style')) {
      s = s
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&apos;', "'")
          .replaceAll('&#x2F;', '/')
          .replaceAll('&#47;', '/')
          .replaceAll('&amp;', '&');
    }

    // 2. Strip leading markdown code fences: ```html, ```xml, ```, ~~~, etc.
    s = s.replaceFirst(RegExp(r'^(`{3,}|~{3,})[a-zA-Z0-9_\-]*\s*\n?'), '');

    // 3. Strip trailing markdown code fences: ``` or ~~~
    s = s.replaceFirst(RegExp(r'\n?(`{3,}|~{3,})\s*$'), '');

    // 4. Repeated check for nested fences
    s = s.trim();
    while (s.startsWith('```') || s.startsWith('~~~')) {
      s = s.replaceFirst(RegExp(r'^(`{3,}|~{3,})[a-zA-Z0-9_\-]*\s*\n?'), '').trim();
    }
    while (s.endsWith('```') || s.endsWith('~~~')) {
      s = s.replaceFirst(RegExp(r'\n?(`{3,}|~{3,})\s*$'), '').trim();
    }

    return s;
  }

  String _extractArtifactTags({
    required String content,
    required String messageId,
    required String conversationId,
    required List<Artifact> artifactsSink,
  }) {
    return content.replaceAllMapped(_artifactTag, (match) {
      final attrs = match.group(1) ?? '';
      final rawBody = (match.group(2) ?? '').trim();
      final body = cleanCode(rawBody);

      String type = _extractAttr(attrs, 'type') ?? _extractAttr(attrs, 'language') ?? 'html';
      String? title = _extractAttr(attrs, 'title');

      final kind = _kindByLanguage[type.toLowerCase()] ??
          (type.contains('html') ? ArtifactKind.html : ArtifactKind.code);

      title = _normalizeTitle(title, kind, type, body);

      final id = 'art-tag-${DateTime.now().microsecondsSinceEpoch}-${artifactsSink.length}';
      final artifact = Artifact(
        id: id,
        messageId: messageId,
        conversationId: conversationId,
        kind: kind,
        language: type.isEmpty ? 'html' : type,
        sourceCode: body,
        title: title,
        meta: const {},
        detectedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: ArtifactStatus.ready,
      );
      artifactsSink.add(artifact);
      return '<!-- artifact:${artifact.id} -->';
    });
  }

  String? _extractAttr(String raw, String name) {
    final m = RegExp('$name=[\'"]([^\'"]+)[\'"]', caseSensitive: false).firstMatch(raw);
    return m?.group(1);
  }

  String _extractFences({
    required String content,
    required String messageId,
    required String conversationId,
    required List<Artifact> artifactsSink,
  }) {
    final lines = content.split('\n');
    final out = <String>[];
    int i = 0;
    while (i < lines.length) {
      final match = _fenceStart.firstMatch(lines[i]);
      if (match == null) {
        out.add(lines[i]);
        i++;
        continue;
      }
      final fenceChar = match.group(1)![0];
      final fenceLen = match.group(1)!.length;
      final language = match.group(2)?.toLowerCase().trim() ?? '';
      final openingLine = i;
      int j = i + 1;
      final buf = <String>[];
      bool closed = false;
      while (j < lines.length) {
        final t = lines[j].trim();
        if ((t.startsWith('```') || t.startsWith('~~~')) &&
            t.length >= fenceLen &&
            t.split('').every((c) => c == fenceChar || c == ' ' || c == '\t')) {
          closed = true;
          break;
        }
        buf.add(lines[j]);
        j++;
      }
      if (!closed) {
        final rawSource = lines.sublist(openingLine + 1).join('\n');
        final source = cleanCode(rawSource);
        if (source.trim().isNotEmpty) {
          final kind = _kindByLanguage[language] ?? ArtifactKind.code;
          final id = 'art-code-${DateTime.now().microsecondsSinceEpoch}-${artifactsSink.length}';
          final artifact = Artifact(
            id: id,
            messageId: messageId,
            conversationId: conversationId,
            kind: kind,
            language: language.isEmpty ? 'text' : language,
            sourceCode: source,
            title: _normalizeTitle(null, kind, language, source),
            meta: const {},
            detectedAt: DateTime.now(),
            updatedAt: DateTime.now(),
            status: ArtifactStatus.ready,
          );
          artifactsSink.add(artifact);
          out.add('<!-- artifact:${artifact.id} -->');
        }
        break;
      }
      final rawSource = buf.join('\n');
      final source = cleanCode(rawSource);
      final kind = _kindByLanguage[language] ?? ArtifactKind.code;
      String? title;
      for (int k = out.length - 1; k >= 0; k--) {
        final t = out[k].trim();
        if (t.isEmpty) continue;
        final h = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(t);
        if (h != null) {
          title = h.group(1)!.trim();
          out.removeAt(k);
          break;
        }
        if (RegExp(r'^[A-Za-z]').hasMatch(t)) break;
      }

      title = _normalizeTitle(title, kind, language, source);

      final id = 'art-code-${DateTime.now().microsecondsSinceEpoch}-${artifactsSink.length}';
      final artifact = Artifact(
        id: id,
        messageId: messageId,
        conversationId: conversationId,
        kind: kind,
        language: language.isEmpty ? 'text' : language,
        sourceCode: source,
        title: title,
        meta: const {},
        detectedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: ArtifactStatus.ready,
      );
      artifactsSink.add(artifact);
      out.add('<!-- artifact:${artifact.id} -->');
      i = j + 1;
    }
    return out.join('\n');
  }

  String _extractRawHtml({
    required String content,
    required String messageId,
    required String conversationId,
    required List<Artifact> artifactsSink,
  }) {
    if (content.length < 20) return content;

    // 1. Check for full HTML document: <!DOCTYPE html> ... </html> or <html>...</html> or unclosed streaming HTML
    final fullDocRegex = RegExp(
      r'(<!DOCTYPE\s+html[\s\S]*?<\/html>|<html[\s\S]*?<\/html>|<svg[\s\S]*?<\/svg>|<!DOCTYPE\s+html[\s\S]*$|<html[\s\S]*$)',
      caseSensitive: false,
    );

    var res = content.replaceAllMapped(fullDocRegex, (m) {
      final rawBody = m.group(1)!.trim();
      final body = cleanCode(rawBody);
      if (body.isEmpty) return '';
      final kind = body.startsWith('<svg') ? ArtifactKind.svg : ArtifactKind.html;
      final lang = kind == ArtifactKind.svg ? 'svg' : 'html';
      final title = _normalizeTitle(null, kind, lang, body);
      final id = 'art-raw-${DateTime.now().microsecondsSinceEpoch}-${artifactsSink.length}';
      final artifact = Artifact(
        id: id,
        messageId: messageId,
        conversationId: conversationId,
        kind: kind,
        language: lang,
        sourceCode: body,
        title: title,
        meta: const {},
        detectedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: ArtifactStatus.ready,
      );
      artifactsSink.add(artifact);
      return '<!-- artifact:${artifact.id} -->';
    });

    // 2. Check for HTML snippet (<div class="..."> ... </div> or <section...>)
    if (artifactsSink.isEmpty && (res.contains('<div') || res.contains('<section') || res.contains('<style>'))) {
      final snippetRegex = RegExp(
        r'(<div\s+class=[\s\S]*?<\/div>|<section[\s\S]*?<\/section>)',
        caseSensitive: false,
      );
      res = res.replaceAllMapped(snippetRegex, (m) {
        final rawBody = m.group(1)!.trim();
        final body = cleanCode(rawBody);
        if (body.length > 50) {
          final title = _normalizeTitle(null, ArtifactKind.html, 'html', body);
          final id = 'art-raw-${DateTime.now().microsecondsSinceEpoch}-${artifactsSink.length}';
          final artifact = Artifact(
            id: id,
            messageId: messageId,
            conversationId: conversationId,
            kind: ArtifactKind.html,
            language: 'html',
            sourceCode: body,
            title: title,
            meta: const {},
            detectedAt: DateTime.now(),
            updatedAt: DateTime.now(),
            status: ArtifactStatus.ready,
          );
          artifactsSink.add(artifact);
          return '<!-- artifact:${artifact.id} -->';
        }
        return m.group(0)!;
      });
    }

    return res;
  }

  static String? _normalizeTitle(String? rawTitle, ArtifactKind kind, String language, String source) {
    var title = rawTitle?.trim();

    // 1) Si no hay título, intentar extraer <title>...</title> de HTML / SVG
    if ((title == null || title.isEmpty) &&
        (kind == ArtifactKind.html || kind == ArtifactKind.svg || language.contains('html') || language.contains('svg'))) {
      final m = RegExp(r'<title[^>]*>([^<]+)<\/title>', caseSensitive: false).firstMatch(source);
      if (m != null) {
        title = m.group(1)?.trim();
      }
    }

    // 2) Si no hay título, revisar si la primera línea del código es un comentario descriptivo
    if (title == null || title.isEmpty) {
      final firstLine = source.trimLeft().split('\n').firstOrNull?.trim() ?? '';
      if (firstLine.startsWith('//') || firstLine.startsWith('#') || firstLine.startsWith('/*')) {
        final cleaned = firstLine
            .replaceFirst(RegExp(r'^(\/\/|#|\/\*+)\s*'), '')
            .replaceFirst(RegExp(r'\*+\/$'), '')
            .trim();
        if (cleaned.length > 2 && cleaned.length < 50 && !cleaned.toLowerCase().startsWith('doctype')) {
          title = cleaned;
        }
      }
    }

    if (title == null || title.isEmpty) return null;

    // 3) Eliminar títulos redundantes que sean iguales al tipo o lenguaje
    final lower = title.toLowerCase();
    final langLower = language.toLowerCase();
    final kindLower = kind.name.toLowerCase();

    if (lower == langLower ||
        lower == kindLower ||
        lower == 'html' ||
        lower == 'svg' ||
        lower == 'mermaid' ||
        lower == 'code' ||
        lower == 'codigo' ||
        lower == 'código' ||
        lower == 'código html' ||
        lower == 'html code' ||
        lower == 'snippet') {
      return null;
    }

    return title;
  }
}
