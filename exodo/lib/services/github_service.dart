import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'github_commit_logic.dart';
import 'supabase_service.dart';

/// [Punto 5] Resultado tipado de un commit de artefacto a GitHub.
class GithubCommitResult {
  final bool ok;
  final String? fileUrl;
  final String? commitUrl;

  const GithubCommitResult({
    required this.ok,
    this.fileUrl,
    this.commitUrl,
  });
}

/// Servicio de integración con GitHub REST API v3 para commitear artefactos.
///
/// POLÍTICA DE SILENCIO (P4/P5): ningún método muestra pop-ups/SnackBars;
/// los fallos se devuelven como `GithubCommitResult(ok:false)` y la UI los
/// comunica INLINE dentro del sheet de consentimiento.
///
/// Resolución de token (en orden):
///   1. PAT enlazado por el usuario vía modal (SharedPreferences por uid).
///   2. `session.providerToken` si la sesión Supabase vino de login GitHub.
class GithubService {
  GithubService._();

// ── Token ────────────────────────────────────────────────────────────────

/// providerToken de sesión (solo presente tras login social con GitHub).
static String? get sessionProviderToken =>
    SupabaseService.client.auth.currentSession?.providerToken;

/// Token operativo: PAT enlazado tiene prioridad; si no, OAuth de sesión.
static Future<String?> resolveLinkedToken() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = githubPatPrefsKeyFor(SupabaseService.currentUser?.id);
    final pat = prefs.getString(key);
    if (pat != null && looksLikePlausibleToken(pat)) return pat.trim();
  } catch (_) {}
  final oauth = sessionProviderToken;
  return (oauth != null && looksLikePlausibleToken(oauth)) ? oauth : null;
}

/// Origen del enlace actual para el indicador del modal: 'pat' | 'oauth' | null.
static Future<String?> linkedTokenKind() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = githubPatPrefsKeyFor(SupabaseService.currentUser?.id);
    final pat = prefs.getString(key);
    if (pat != null && looksLikePlausibleToken(pat)) return 'pat';
  } catch (_) {}
  return sessionProviderToken != null ? 'oauth' : null;
}

/// Enlaza (guarda) el PAT de la cuenta actual. El consentimiento explícito
/// ocurre en el modal donde el usuario escribe voluntariamente el token.
static Future<void> saveLinkedToken(String token) async {
  final t = token.trim();
  if (!looksLikePlausibleToken(t)) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
      githubPatPrefsKeyFor(SupabaseService.currentUser?.id), t);
}

static Future<void> clearLinkedToken() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(githubPatPrefsKeyFor(SupabaseService.currentUser?.id));
}

// ── Prellenado del modal (último repo/ruta usados) ───────────────────────

static Future<(String?, String?)> loadLastCommitPrefill() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = githubLastRepoPrefsKeyFor(SupabaseService.currentUser?.id);
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return (null, null);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return (null, null);
    final repo = decoded['owner_repo']?.toString();
    final path = decoded['path']?.toString();
    return ((repo != null && repo.isNotEmpty) ? repo : null,
        (path != null && path.isNotEmpty) ? path : null);
  } catch (_) {
    return (null, null);
  }
}

static Future<void> rememberLastCommit(
    String ownerRepo, String filePath) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      githubLastRepoPrefsKeyFor(SupabaseService.currentUser?.id),
      jsonEncode({'owner_repo': ownerRepo, 'path': filePath}),
    );
  } catch (_) {}
}

// ─── Commit principal ─────────────────────────────────────────────────────

/// Crea o actualiza `{path}` en `{owner}/{repo}` @branch vía
/// `PUT /repos/{owner}/{repo}/contents/{path}`.
///
/// Si el archivo ya existe en la rama consulta su SHA primero (la API lo
/// exige para actualizar). Todo fallo devuelve ok:false — jamás lanza UI.
static Future<GithubCommitResult> commitFile({
  required String token,
  required String owner,
  required String repo,
  required String path,
  required String message,
  required String fileContent,
  String branch = 'main',
}) async {
  final t = token.trim();
  if (!looksLikePlausibleToken(t)) return const GithubCommitResult(ok: false);

  final url = contentsApiUrl(owner: owner, repo: repo, path: path);
  final headers = <String, String>{
    'Authorization': 'Bearer $t',
    'Accept': 'application/vnd.github+json',
    'Content-Type': 'application/json',
  };

  try {
    final payload = buildPutPayload(
      commitMessage: message,
      fileContent: fileContent,
      branch: branch,
    );

    final sha =
        await _fetchExistingSha(url: url, headers: headers, branch: branch);
    if (sha != null && sha.isNotEmpty) payload['sha'] = sha;

    final response = await http
        .put(Uri.parse(url), headers: headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final (fileUrl, commitUrl) = extractUrlsFromGithubResponse(decoded);
        debugPrint('[GithubService] Commit OK → ${fileUrl ?? url}');
        return GithubCommitResult(
            ok: true, fileUrl: fileUrl, commitUrl: commitUrl);
      }
      return const GithubCommitResult(ok: true);
    }

    debugPrint('[GithubService] PUT falló ${response.statusCode}');
    return const GithubCommitResult(ok: false);
  } catch (_) {
    // Silencio: red/backend abajo → la UI muestra el error inline del sheet.
    return const GithubCommitResult(ok: false);
  }
}

/// SHA del contenido existente en [branch] (null si no existe o falla).
static Future<String?> _fetchExistingSha({
  required String url,
  required Map<String, String> headers,
  required String branch,
}) async {
  try {
    final sep = url.contains('?') ? '&' : '?';
    final res = await http
        .get(Uri.parse('$url${sep}ref=$branch'), headers: headers)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) {
        final sha = data['sha']?.toString();
        return (sha != null && sha.isNotEmpty) ? sha : null;
      }
    }
  } catch (_) {}
  return null;
}
}


