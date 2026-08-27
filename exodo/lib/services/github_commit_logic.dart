/// [Punto 5] Lógica PURA de la integración GitHub Commits (Artefactos → repo).
///
/// Este archivo es Dart puro a propósito (sin Flutter ni plugins): los unit
/// tests importan exactamente el mismo código que ejecuta producción, sin
/// réplicas — patrón establecido con `expedientes_access_policy.dart`.
library;

import 'dart:convert';

// ─── Almacenamiento por cuenta (mismo patrón RLS que expedientes) ───────────

/// Llave SharedPreferences del PAT enlazado, scopeada por uid
/// (null/vacío → 'anon'). Nunca mezclar tokens entre cuentas.
String githubPatPrefsKeyFor(String? uid) {
  final scope = (uid == null || uid.isEmpty) ? 'anon' : uid;
  return 'exodo_github_pat_$scope';
}

/// Llave del último `owner/repo` usado, para prellenar el modal de commit.
String githubLastRepoPrefsKeyFor(String? uid) {
  final scope = (uid == null || uid.isEmpty) ? 'anon' : uid;
  return 'exodo_gh_last_repo_$scope';
}

// ─── Validaciones de entrada del modal ──────────────────────────────────────

final RegExp _slugRe = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$');

/// Slug válido de owner o repo en GitHub: alfanumérico (y . _ -) sin empezar
/// ni terminar por separador; máximo razonable 100 chars.
bool isValidRepoSlug(String s) {
  final t = s.trim();
  if (t.isEmpty || t.length > 100) return false;
  return _slugRe.hasMatch(t);
}

/// Separa `owner/repo` aceptando también la URL completa de GitHub.
/// Devuelve (null, null) si la entrada no produce un par válido.
(String?, String?) parseOwnerRepo(String input) {
  var t = input.trim();
  if (t.isEmpty) return (null, null);

  // https://github.com/owner/repo(.git)(/tree/...) o git@github.com:owner/repo.git
  final m = RegExp(r'github\.com[/:]([^/\s]+)/([^/\s#]+)').firstMatch(t);
  if (m != null) {
    var repo = m.group(2)!;
    if (repo.toLowerCase().endsWith('.git')) {
      repo = repo.substring(0, repo.length - 4);
    }
    final owner = m.group(1)!;
    if (isValidRepoSlug(owner) && isValidRepoSlug(repo)) {
      return (owner, repo);
    }
    return (null, null);
  }

  // Forma corta 'owner/repo' (un solo separador).
  final parts = t.split('/');
  if (parts.length == 2 &&
      isValidRepoSlug(parts[0]) &&
      isValidRepoSlug(parts[1])) {
    return (parts[0].trim(), parts[1].trim());
  }
  return (null, null);
}

/// Ruta segura dentro del repo: sin '.', '..', ':'; '\' convertida a '/';
/// no absoluta; sin segmentos vacíos; longitud total ≤ 250.
bool isValidFilePath(String path) {
  final p = path.trim().replaceAll('\\', '/');
  if (p.isEmpty || p.length > 250) return false;
  if (p.startsWith('/')) return false;
  if (p.contains(':')) return false;
  for (final seg in p.split('/')) {
    if (seg.isEmpty || seg == '.' || seg == '..') return false;
  }
  return true;
}

/// Base de nombre de archivo segura a partir de un título cualquiera:
/// minúsculas, sólo [a-z0-9-_], guiones colapsados, sin bordes de guion.
String sanitizeFileNameBase(String raw) {
  var base = raw.trim().isEmpty ? 'artefacto-exodo' : raw.trim();
  base = base
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\-_ ]'), '')
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'-+'), '-');
  while (base.startsWith('-')) {
    base = base.substring(1);
  }
  while (base.endsWith('-')) {
    base = base.substring(0, base.length - 1);
  }
  return base.isEmpty ? 'artefacto-exodo' : base;
}

/// Extensión sugerida a partir del lenguaje/plan del artefacto.
String defaultExtForLanguage(String language) {
  switch (language.trim().toLowerCase()) {
    case 'markdown':
    case 'md':
      return 'md';
    case 'javascript':
    case 'js':
    case 'jsx':
    case 'mjs':
      return 'js';
    case 'typescript':
    case 'ts':
    case 'tsx':
      return 'ts';
    case 'python':
    case 'py':
      return 'py';
    case 'html':
    case 'htm':
      return 'html';
    case 'svg':
      return 'svg';
    case 'css':
      return 'css';
    case 'json':
      return 'json';
    case 'sql':
      return 'sql';
    case 'dart':
      return 'dart';
    case 'yaml':
    case 'yml':
      return 'yaml';
    default:
      return 'txt';
  }
}

/// Ruta por defecto para un artefacto: `src/artifacts/<slug>.<ext>`
String defaultFilePathFor({required String title, required String ext}) =>
    'src/artifacts/${sanitizeFileNameBase(title)}.$ext';

/// Mensaje por defecto pedido por producto: feat(exodo): add {title} artifact
String defaultCommitMessage(String artifactTitle) {
  final title = artifactTitle.trim();
  final safeTitle = sanitizeFileNameBase(title) == 'artefacto-exodo'
      ? 'artifact'
      : title;
  return 'feat(exodo): add $safeTitle artifact';
}

// ─── Payload y URL de la GitHub REST API v3 ─────────────────────────────────

/// PUT /repos/{owner}/{repo}/contents/{path}
String contentsApiUrl({
  required String owner,
  required String repo,
  required String path,
}) {
  final cleanPath =
      path.trim().replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');
  return 'https://api.github.com/repos/$owner/$repo/contents/$cleanPath';
}

/// Content-base64 del archivo (UTF-8), exigido por la API de contents.
String encodeFileContent(String source) => base64.encode(utf8.encode(source));

/// Body del PUT. Mensaje vacío cae al mensaje por defecto; rama vacía → main.
Map<String, dynamic> buildPutPayload({
  required String commitMessage,
  required String fileContent,
  String branch = 'main',
}) {
  final msg = commitMessage.trim().isNotEmpty
      ? commitMessage.trim()
      : defaultCommitMessage('artifact');
  return <String, dynamic>{
    'message': msg,
    'content': encodeFileContent(fileContent),
    'branch': branch.trim().isEmpty ? 'main' : branch.trim(),
  };
}

/// PAT plausible heurísticamente: largo suficiente y sin espacios.
/// No valida contra la API — eso lo hace el propio PUT.
bool looksLikePlausibleToken(String token) {
  final t = token.trim();
  return t.length >= 20 && !t.contains(' ');
}

/// Extrae (fileUrl, commitUrl) del JSON de éxito de la API de contents.
/// Shape nuevo: {content:{html_url}, commit:{html_url}}.
(String?, String?) extractUrlsFromGithubResponse(Map<String, dynamic> json) {
  String? fileUrl;
  String? commitUrl;

  final content = json['content'];
  if (content is Map<String, dynamic>) {
    final u = content['html_url']?.toString() ?? '';
    if (u.isNotEmpty) fileUrl = u;
  }
  final commit = json['commit'];
  if (commit is Map<String, dynamic>) {
    final u = commit['html_url']?.toString() ?? '';
    if (u.isNotEmpty) commitUrl = u;
  }
  return (fileUrl, commitUrl);
}


