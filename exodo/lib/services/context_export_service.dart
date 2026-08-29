// ═══════════════════════════════════════════════════════════════════════════════
// CONTEXT EXPORT SERVICE — "Exportar contexto" de un chat largo
// ───────────────────────────────────────────────────────────────────────────────
// Genera un HTML standalone (doble clic = legible por humanos; texto plano
// estructurado = comprensible por Éxodo o cualquier IA al reimportarlo) con la
// transcripción completa del chat y un bloque JSON embebido machine-readable.
//
// Flujo de usuario (límite de contexto de un chat):
//   1. Banner avisa que el chat se acerca a su límite de memoria.
//   2. "Exportar contexto" → comparte el HTML por el Share Sheet nativo.
//   3. Usuario inicia un chat nuevo y ADJUNTA el HTML: el backend lo extrae
//      (documentExtractor soporta text/html) y el modelo continúa el contexto.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'export/exporters.dart' show ShareService;

class ContextExportService {
  ContextExportService._();

  /// Escapa HTML preserving saltos de línea (se convierten a <br> aparte).
  static String _esc(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  /// Construye el HTML completo del contexto. `labels` debe traer las cadenas
  /// ya localizadas (transcript / roleUser / roleAi / reimportHint).
  static String buildContextHtml({
    required String title,
    required String locale,
    required List<ChatMessage> messages,
    required String transcriptLabel,
    required String roleUserLabel,
    required String roleAiLabel,
    required String reimportHint,
  }) {
    final now = DateTime.now();
    final exportedAt = now.toUtc().toIso8601String();

    // Bloque machine-readable: cualquier IA (o Éxodo reimportando) puede leer
    // el JSON completo sin depender del parseo del HTML visible.
    final payload = <String, dynamic>{
      'exodo_context': 1,
      'title': title,
      'locale': locale,
      'exported_at': exportedAt,
      'messages': messages
          .where((m) => !m.isThinking && m.content.trim().isNotEmpty)
          .map((m) => {
                'role': m.role,
                'content': m.content,
                'created_at': m.createdAt.toIso8601String(),
              })
          .toList(),
    };
    final jsonBlock = const JsonEncoder.withIndent(' ').convert(payload);

    final sb = StringBuffer();
    sb.writeln('<!DOCTYPE html>');
    sb.writeln('<html lang="${_esc(locale)}">');
    sb.writeln('<head>');
    sb.writeln('<meta charset="utf-8">');
    sb.writeln('<meta name="viewport" content="width=device-width, initial-scale=1">');
    sb.writeln('<meta name="exodo-context" content="v1">');
    sb.writeln('<title>${_esc(title)}</title>');
    sb.writeln('<style>');
    sb.writeln('body{font-family:-apple-system,"Segoe UI",Roboto,sans-serif;max-width:760px;margin:0 auto;padding:24px;line-height:1.5;color:#1a1a1a;background:#faf9f5}');
    sb.writeln('h1{font-size:1.3rem;border-bottom:2px solid #d97706;padding-bottom:8px}');
    sb.writeln('.meta{color:#6b7280;font-size:.85rem;margin-bottom:20px}');
    sb.writeln('.msg{margin:14px 0;padding:12px 16px;border-radius:12px;border:1px solid #e5e1d8;background:#fff}');
    sb.writeln('.user{background:#fdf6e3;border-color:#f0dfb2}');
    sb.writeln('.role{font-weight:700;font-size:.8rem;text-transform:uppercase;letter-spacing:.05em;color:#92400e;margin-bottom:6px}');
    sb.writeln('.ai .role{color:#2563eb}');
    sb.writeln('.content{white-space:pre-wrap;word-wrap:break-word;font-size:.95rem}');
    sb.writeln('.hint{margin-top:24px;padding:12px 16px;border-radius:12px;background:#eff6ff;border:1px solid #bfdbfe;color:#1e40af;font-size:.9rem}');
    sb.writeln('footer{margin-top:28px;color:#9ca3af;font-size:.75rem;text-align:center}');
    sb.writeln('</style>');
    sb.writeln('</head>');
    sb.writeln('<body>');
    sb.writeln('<h1>${_esc(title)}</h1>');
    sb.writeln('<div class="meta">Éxodo by Behavior · $transcriptLabel · ${_esc(now.toLocal().toString().split('.').first)}</div>');
    sb.writeln('<script type="application/json" id="exodo-context-data">');
    sb.writeln(jsonBlock);
    sb.writeln('</script>');

    for (final m in messages) {
      if (m.isThinking || m.content.trim().isEmpty) continue;
      final isUser = m.role == 'user';
      final roleLabel = isUser ? roleUserLabel : roleAiLabel;
      sb.writeln('<div class="msg ${isUser ? 'user' : 'ai'}">');
      sb.writeln('<div class="role">${_esc(roleLabel)}</div>');
      sb.writeln('<div class="content">${_esc(m.content)}</div>');
      sb.writeln('</div>');
    }

    sb.writeln('<div class="hint">💡 ${_esc(reimportHint)}</div>');
    sb.writeln('<footer>Éxodo by Behavior · exodo-context v1 · $exportedAt</footer>');
    sb.writeln('</body>');
    sb.writeln('</html>');
    return sb.toString();
  }

  /// Genera el HTML y lo abre en el Share Sheet nativo. No-op en Web.
  static Future<bool> exportAndShare({
    required String title,
    required String locale,
    required List<ChatMessage> messages,
    required String transcriptLabel,
    required String roleUserLabel,
    required String roleAiLabel,
    required String reimportHint,
  }) async {
    if (kIsWeb) return false;
    try {
      final html = buildContextHtml(
        title: title,
        locale: locale,
        messages: messages,
        transcriptLabel: transcriptLabel,
        roleUserLabel: roleUserLabel,
        roleAiLabel: roleAiLabel,
        reimportHint: reimportHint,
      );
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final safeTitle = title
          .replaceAll(RegExp(r'[^\w\- ]'), '')
          .trim()
          .replaceAll(' ', '-')
          .toLowerCase();
      final file = File('${dir.path}/exodo-context-${safeTitle.isEmpty ? 'chat' : safeTitle}-$stamp.html');
      await file.writeAsString(html, flush: true);
      await ShareService.instance.shareFile(
        file,
        subject: title,
        text: reimportHint,
      );
      return true;
    } catch (e) {
      debugPrint('[ContextExport] falló: $e');
      return false;
    }
  }
}
