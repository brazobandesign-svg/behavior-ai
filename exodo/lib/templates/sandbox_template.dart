import '../../data/artifacts/artifact.dart';

/// Sandbox Template for secure, isolated rendering of executable artifacts.
class SandboxTemplate {
  SandboxTemplate._();

  static const String darkCanvasBg = '#121212';
  static const String darkText = '#F5F2EB';
  static const String monoBg = '#1E1E1E';
  static const String monoFg = '#F5F2EB';

  /// Dominio CDN seguro permitido SOLO para Mermaid (librería externa requerida).
  static const String _allowedCdnHost = 'https://cdn.jsdelivr.net';

  /// Construye el HTML final con cabecera CSP estricta y metadatos
  /// según el tipo de artefacto.
  static String wrap({required ArtifactKind kind, required String source}) {
    final trimmed = source.trimLeft().toLowerCase();
    final isFullDoc =
        trimmed.startsWith('<!doctype') || trimmed.startsWith('<html');

    if (isFullDoc) {
      return source;
    }

    final sanitized = sanitize(kind: kind, source: source);
    switch (kind) {
      case ArtifactKind.html:
      case ArtifactKind.react:
      case ArtifactKind.vue:
        return _wrapFullDoc(sanitized);
      case ArtifactKind.svg:
        return _wrapSvg(sanitized);
      case ArtifactKind.mermaid:
        return _wrapMermaid(sanitized);
      case ArtifactKind.latex:
        return _wrapFullDoc('<div class="latex-source">${_escape(source)}</div>');
      case ArtifactKind.diagram:
        return _wrapFullDoc('<pre>${_escape(source)}</pre>');
      case ArtifactKind.code:
      case ArtifactKind.json:
      case ArtifactKind.table:
        return _wrapFullDoc('<pre class="raw-source">${_escape(source)}</pre>');
    }
  }

  /// Cadena de cabecera CSP aplicada en la respuesta HTTP del iframe y
  /// duplicada como <meta> en el HTML del sandbox.
  static String cspHeader({bool allowMermaidCdn = false}) {
    final scriptSrc = allowMermaidCdn
        ? "'unsafe-inline' 'unsafe-eval' $_allowedCdnHost"
        : "'unsafe-inline' 'unsafe-eval'";
    final styleSrc = allowMermaidCdn
        ? "'unsafe-inline' $_allowedCdnHost"
        : "'unsafe-inline'";
    return 'default-src \'none\'; '
        'script-src $scriptSrc; '
        'style-src $styleSrc; '
        'img-src data: https:; '
        'font-src data:; '
        'connect-src ${allowMermaidCdn ? _allowedCdnHost : '\'none\''}; '
        'frame-src \'none\'; '
        'object-src \'none\'; '
        'base-uri \'none\';';
  }

  /// Sanitización regex de 4 capas para defensa en profundidad.
  static String sanitize({required ArtifactKind kind, required String source}) {
    var s = source;

    // 1) Tags prohibidos
    const forbidden = [
      '<script src',
      '<link',
      '<iframe',
      '<object',
      '<embed',
      '<base',
      '<meta http-equiv="refresh"',
    ];
    for (final t in forbidden) {
      s = s.replaceAll(RegExp(RegExp.escape(t), caseSensitive: false), '<!--blocked-->');
    }

    // 2) Event handlers inline
    s = s.replaceAllMapped(
      RegExp(r'\son\w+\s*=\s*"[^"]*"', caseSensitive: false),
      (m) => '',
    );
    s = s.replaceAllMapped(
      RegExp(r"\son\w+\s*=\s*'[^']*'", caseSensitive: false),
      (m) => '',
    );
    s = s.replaceAllMapped(
      RegExp(r'\son\w+\s*=\s*\S+', caseSensitive: false),
      (m) => '',
    );

    // 3) URIs javascript: en href/src
    s = s.replaceAllMapped(
      RegExp(r'(href|src)\s*=\s*"javascript:[^"]*"', caseSensitive: false),
      (m) => '${m[1]}="#"',
    );
    s = s.replaceAllMapped(
      RegExp(r"(href|src)\s*=\s*'javascript:[^']*'", caseSensitive: false),
      (m) => '${m[1]}="#"',
    );

    // 4) Para Mermaid, el DSL es texto plano
    if (kind == ArtifactKind.mermaid) return s;

    return s;
  }

  static String _wrapFullDoc(String body) {
    final trimmed = body.trimLeft().toLowerCase();
    final isFullDoc =
        trimmed.startsWith('<!doctype') || trimmed.startsWith('<html');

    // Documento completo: pasar TAL CUAL al WebView. NO re-envolver con otro
    // <!DOCTYPE> ni <body> (el doble envoltorio rompe el render → pantalla
    // en blanco/negra).
    if (isFullDoc) {
      return body;
    }

    // Snippet HTML (p. ej. <div>...</div>): envolver en el canvas estándar.
    return '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes">
  <meta http-equiv="Content-Security-Policy" content="${cspHeader()}">
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
    body { padding: 16px; box-sizing: border-box; width: 100%; }
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
    final csp = cspHeader(allowMermaidCdn: true);
    return '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes">
  <meta http-equiv="Content-Security-Policy" content="$csp">
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
    body { padding: 20px; box-sizing: border-box; }
    .mermaid { font-family: system-ui, -apple-system, sans-serif; color: #F5F2EB; }
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

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
