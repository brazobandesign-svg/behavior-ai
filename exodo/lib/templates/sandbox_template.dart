import '../../data/artifacts/artifact.dart';

/// Sandbox Template for secure, isolated rendering of executable artifacts.
class SandboxTemplate {
  SandboxTemplate._();

  static const String darkCanvasBg = '#121212';
  static const String darkText = '#F5F2EB';
  static const String monoBg = '#1E1E1E';
  static const String monoFg = '#F5F2EB';

  /// Dominio CDN seguro permitido para Mermaid (librería externa requerida).
  static const String _allowedCdnHost = 'https://cdn.jsdelivr.net';

  /// Cleans markdown fences, backticks, and HTML entities from raw source code.
  static String cleanSource(String raw) {
    if (raw.trim().isEmpty) return '';
    var s = raw.trim();

    // 1. Unescape HTML entities if detected in document tags or HTML wrapper
    if (s.startsWith('&lt;') ||
        s.contains('&lt;!DOCTYPE') ||
        s.contains('&lt;html') ||
        s.contains('&lt;div') ||
        s.contains('&lt;svg') ||
        s.contains('&lt;script') ||
        s.contains('&lt;style')) {
      s = _unescapeHtmlEntities(s);
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

  /// Construye el HTML final listo para renderizar en InAppWebView.
  /// Permissive CSP meta tag for local sandbox execution without blocking scripts/DOM.
  static const String permissiveCspMeta =
      '<meta http-equiv="Content-Security-Policy" content="default-src * \'unsafe-inline\' \'unsafe-eval\' data: blob:; script-src * \'unsafe-inline\' \'unsafe-eval\' data: blob: https: http:; style-src * \'unsafe-inline\' https: http:; img-src * data: blob: https: http:; font-src * data: https: http:; connect-src *;">';

  /// Auto-dispatch polyfill for DOMContentLoaded and load events.
  /// In WebViews loaded via loadData, scripts registered after initial DOM parse
  /// may miss DOMContentLoaded; this guarantees any listener executes immediately.
  static const String domReadyPolyfill = '''<script>
(function() {
  var _origDocAdd = document.addEventListener;
  document.addEventListener = function(type, listener, options) {
    if (type === 'DOMContentLoaded' && (document.readyState === 'interactive' || document.readyState === 'complete')) {
      setTimeout(function() {
        try {
          if (typeof listener === 'function') listener(new Event('DOMContentLoaded'));
          else if (listener && typeof listener.handleEvent === 'function') listener.handleEvent(new Event('DOMContentLoaded'));
        } catch(e) { console.error('[Sandbox DOMContentLoaded Polyfill]', e); }
      }, 1);
    }
    return _origDocAdd.call(document, type, listener, options);
  };
  var _origWinAdd = window.addEventListener;
  window.addEventListener = function(type, listener, options) {
    if (type === 'load' && document.readyState === 'complete') {
      setTimeout(function() {
        try {
          if (typeof listener === 'function') listener(new Event('load'));
          else if (listener && typeof listener.handleEvent === 'function') listener.handleEvent(new Event('load'));
        } catch(e) { console.error('[Sandbox load Polyfill]', e); }
      }, 1);
    }
    return _origWinAdd.call(window, type, listener, options);
  };
})();
</script>''';

  /// Construye el HTML final listo para renderizar en InAppWebView.
  static String wrap({required ArtifactKind kind, required String source}) {
    final cleaned = cleanSource(source);
    final trimmed = cleaned.trimLeft().toLowerCase();
    final isFullDoc =
        trimmed.startsWith('<!doctype') || trimmed.startsWith('<html');

    // Documento completo: inyectar polyfill de reactividad y asegurar CSP permisivo
    if (isFullDoc) {
      return _injectHeadSafeguards(cleaned);
    }

    switch (kind) {
      case ArtifactKind.html:
      case ArtifactKind.react:
      case ArtifactKind.vue:
        return _wrapFullDoc(cleaned);
      case ArtifactKind.svg:
        return _wrapSvg(cleaned);
      case ArtifactKind.mermaid:
        return _wrapMermaid(cleaned);
      case ArtifactKind.latex:
        return _wrapFullDoc('<div class="latex-source">${_escape(cleaned)}</div>');
      case ArtifactKind.diagram:
        return _wrapFullDoc('<pre>${_escape(cleaned)}</pre>');
      case ArtifactKind.code:
      case ArtifactKind.json:
      case ArtifactKind.table:
        return _wrapFullDoc('<pre class="raw-source">${_escape(cleaned)}</pre>');
    }
  }

  /// Inyecta el CSP permisivo y el polyfill de DOMContentLoaded dentro del `<head>` de un documento completo.
  static String _injectHeadSafeguards(String fullHtml) {
    final headMatch = RegExp(r'<head(\s*[^>]*)>', caseSensitive: false).firstMatch(fullHtml);
    if (headMatch != null) {
      final insertIndex = headMatch.end;
      final before = fullHtml.substring(0, insertIndex);
      final after = fullHtml.substring(insertIndex);
      return '$before\n  $permissiveCspMeta\n  $domReadyPolyfill\n$after';
    }

    final htmlMatch = RegExp(r'<html(\s*[^>]*)>', caseSensitive: false).firstMatch(fullHtml);
    if (htmlMatch != null) {
      final insertIndex = htmlMatch.end;
      final before = fullHtml.substring(0, insertIndex);
      final after = fullHtml.substring(insertIndex);
      return '$before\n<head>\n  $permissiveCspMeta\n  $domReadyPolyfill\n</head>\n$after';
    }

    return '<head>\n  $permissiveCspMeta\n  $domReadyPolyfill\n</head>\n$fullHtml';
  }

  /// Cadena de cabecera CSP permisiva para ejecución interactiva local sin bloquear DOM/JS.
  static String cspHeader({bool allowMermaidCdn = false}) {
    final scriptSrc = allowMermaidCdn
        ? "'unsafe-inline' 'unsafe-eval' https: http: data: blob: $_allowedCdnHost"
        : "'unsafe-inline' 'unsafe-eval' https: http: data: blob:";
    return "default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; "
        "script-src $scriptSrc; "
        "style-src * 'unsafe-inline' https: http:; "
        "img-src * data: blob: https: http:; "
        "font-src * data: https: http:; "
        "connect-src *; "
        "media-src * data: blob:;";
  }

  /// Sanitización suave que no elimina event handlers interactivos ni etiquetas funcionales.
  static String sanitize({required ArtifactKind kind, required String source}) {
    return cleanSource(source);
  }

  static String _wrapFullDoc(String body) {
    final trimmed = body.trimLeft().toLowerCase();
    final isFullDoc =
        trimmed.startsWith('<!doctype') || trimmed.startsWith('<html');

    if (isFullDoc) {
      return _injectHeadSafeguards(body);
    }

    // Snippet HTML: envolver en el canvas estándar con soporte de estilos oscuros y viewport responsivo
    return '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes">
  $permissiveCspMeta
  $domReadyPolyfill
  <style>
    * { box-sizing: border-box; }
    html, body {
      background-color: #121212;
      color: #F5F2EB;
      margin: 0;
      padding: 16px;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      min-height: 100vh;
      width: 100%;
    }
    img, svg { max-width: 100%; height: auto; display: block; }
    pre { background: #1E1E1E; color: #F5F2EB; padding: 12px; border-radius: 8px; overflow-x: auto; font-family: ui-monospace, 'SF Mono', Menlo, Consolas, monospace; font-size: 12px; }
    pre.raw-source { white-space: pre-wrap; word-wrap: break-word; }
  </style>
</head>
<body>
$body
</body>
</html>''';
  }

  static String _wrapSvg(String body) {
    var s = body;
    if (!s.contains('xmlns=')) {
      s = s.replaceFirst('<svg', '<svg xmlns="http://www.w3.org/2000/svg"');
    }
    return _wrapFullDoc(s);
  }

  static String _wrapMermaid(String source) {
    return '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes">
  <style>
    html, body {
      background-color: #121212;
      color: #F5F2EB;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      margin: 0;
      font-family: system-ui, -apple-system, sans-serif;
    }
    body { padding: 20px; box-sizing: border-box; width: 100%; }
    .mermaid { font-family: system-ui, -apple-system, sans-serif; color: #F5F2EB; text-align: center; }
    .mermaid-error { color: #B85A4A; padding: 16px; background: rgba(184,90,74,0.08); border-radius: 8px; border: 1px solid #B85A4A; }
  </style>
</head>
<body>
  <pre class="mermaid">${_escape(source)}</pre>
  <script src="$_allowedCdnHost/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>
  <script>
    (function() {
      function fail(msg) {
        var box = document.createElement('div');
        box.className = 'mermaid-error';
        box.textContent = 'No se pudo renderizar Mermaid: ' + msg;
        var pre = document.querySelector('pre.mermaid');
        if (pre && pre.parentNode) pre.parentNode.insertBefore(box, pre);
      }
      if (typeof mermaid === 'undefined') {
        fail('la librería no se cargó (posible CSP de red o sin conexión)');
        return;
      }
      try {
        mermaid.initialize({
          startOnLoad: true,
          theme: 'dark',
          securityLevel: 'strict',
          fontFamily: 'system-ui, -apple-system, sans-serif',
          themeVariables: { fontSize: '14px', darkMode: true, background: '#121212' }
        });
      } catch (e) { fail(e && e.message ? e.message : String(e)); }
    })();
  </script>
</body>
</html>''';
  }

  static String _unescapeHtmlEntities(String text) {
    return text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&#x2F;', '/')
        .replaceAll('&#47;', '/')
        .replaceAll('&amp;', '&');
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
