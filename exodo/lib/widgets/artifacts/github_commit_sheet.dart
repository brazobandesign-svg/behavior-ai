import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/artifacts/artifact.dart';
import '../../l10n/app_i18n.dart';
import '../../services/app_state.dart';
import '../../services/github_commit_logic.dart';
import '../../services/github_service.dart';
import '../../theme/exodo_palette.dart';

/// [Punto 5] Modal de enlace y confirmación para commitear un artefacto a
/// GitHub. Regla estricta de consentimiento: nada se envía sin que el usuario
/// defina repo/ruta/mensaje/rama y presione el botón explícito.
///
/// Errores SIEMPRE inline en el sheet — cero pop-ups nativos (política P4/P5).
class GithubCommitSheet extends StatefulWidget {
  final Artifact artifact;

  const GithubCommitSheet({super.key, required this.artifact});

  @override
  State<GithubCommitSheet> createState() => _GithubCommitSheetState();
}

class _GithubCommitSheetState extends State<GithubCommitSheet> {
  late final TextEditingController _repoCtrl;
  late final TextEditingController _pathCtrl;
  late final TextEditingController _msgCtrl;
  final TextEditingController _branchCtrl =
      TextEditingController(text: 'main');
  final TextEditingController _patCtrl = TextEditingController();

  bool _busy = false;
  bool _showPatField = false;
  String? _error;
  GithubCommitResult? _result;
  String? _linkedKind; // 'pat' | 'oauth' | null
  final Set<String> _copiedUrls = {};

  // Bordes rojos por campo inválido (feedback visual, no pop-ups).
  bool _repoBad = false;
  bool _pathBad = false;
  bool _branchBad = false;

  @override
  void initState() {
    super.initState();
    final a = widget.artifact;
    final ext = defaultExtForLanguage(a.language);
    _repoCtrl = TextEditingController();
    _pathCtrl =
        TextEditingController(text: defaultFilePathFor(title: a.title ?? '', ext: ext));
    _msgCtrl = TextEditingController(text: defaultCommitMessage(a.title ?? ''));

    _hydratePrefill();
  }

  Future<void> _hydratePrefill() async {
    try {
      final (lastRepo, lastPath) = await GithubService.loadLastCommitPrefill();
      final kind = await GithubService.linkedTokenKind();
      if (!mounted) return;
      setState(() {
        if (lastRepo != null && _repoCtrl.text.trim().isEmpty) {
          _repoCtrl.text = lastRepo;
        }
        if (lastPath != null && isValidFilePath(lastPath)) {
          _pathCtrl.text = lastPath;
        }
        _linkedKind = kind;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _repoCtrl.dispose();
    _pathCtrl.dispose();
    _msgCtrl.dispose();
    _branchCtrl.dispose();
    _patCtrl.dispose();
    super.dispose();
  }

  Future<void> _onCommit() async {
    if (_busy || _result != null) return;
    final i18n = AppI18n.of(context);

    // Defensa extra: aunque la entrada esté oculta para invitados.
    if (!context.read<AppState>().isOnline ||
        context.read<AppState>().isGuestUser) {
      HapticFeedback.vibrate();
      setState(() => _error = i18n.t('github.error'));
      return;
    }

    final (owner, repo) = parseOwnerRepo(_repoCtrl.text);
    final pathOk = isValidFilePath(_pathCtrl.text);
    final branchOk =
        RegExp(r'^[A-Za-z0-9._\/-]+$').hasMatch(_branchCtrl.text.trim()) &&
            _branchCtrl.text.trim().isNotEmpty;

    var invalid = false;
    setState(() {
      _error = null;
      _repoBad = owner == null;
      _pathBad = !pathOk;
      _branchBad = !branchOk;
      if (_repoBad || _pathBad || _branchBad) invalid = true;
    });
    if (invalid) {
      HapticFeedback.selectionClick();
      return;
    }

    // Resolución de token: PAT tecleado ahora > PAT enlazado > OAuth sesión.
    final patTyped = _patCtrl.text.trim();
    String? token;
    String? usedPat;
    if (patTyped.isNotEmpty && looksLikePlausibleToken(patTyped)) {
      token = patTyped;
      usedPat = patTyped;
    } else {
      token = await GithubService.resolveLinkedToken();
    }

    if (!mounted) return;
    if (token == null) {
      HapticFeedback.selectionClick();
      setState(() {
        _showPatField = true;
        _error = i18n.t('github.link_required');
      });
      return;
    }

    setState(() => _busy = true);
    final res = await GithubService.commitFile(
      token: token,
      owner: owner!,
      repo: repo!,
      path: _pathCtrl.text.trim(),
      message: _msgCtrl.text,
      fileContent: widget.artifact.sourceCode,
      branch: _branchCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok) {
        _result = res;
        // Persistir contexto del éxito para próximas veces.
        GithubService.rememberLastCommit(
            '${_repoCtrl.text.trim().split('/').first}/${_repoCtrl.text.trim().split('/').last}',
            _pathCtrl.text.trim());
        if (usedPat != null) GithubService.saveLinkedToken(usedPat);
        HapticFeedback.lightImpact();
      } else {
        _error = i18n.t('github.error');
        HapticFeedback.selectionClick();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const chalk = Color(0xFFF5F2EB);
    final primaryText = isDark ? chalk : const Color(0xFF191919);
    final secondaryText = isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73);
    final fieldFill = isDark ? const Color(0xFF252525) : const Color(0xFFEAE7E0);

    InputDecoration deco(String hintKey, {bool bad = false}) => InputDecoration(
          isDense: true,
          filled: true,
          fillColor: fieldFill,
          hintText: i18n.t(hintKey),
          hintStyle: TextStyle(
              fontFamily: 'AnthropicSans',
              fontSize: 12.5,
              color: secondaryText),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: bad ? Colors.redAccent : (isDark ? Colors.white12 : Colors.black12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: bad ? Colors.redAccent : ExodoPalette.gold, width: 1.4),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_tree_outlined,
                      color: ExodoPalette.gold, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      i18n.t('github.sheet_title'),
                      style: TextStyle(
                        fontFamily: 'AnthropicSans',
                        color: primaryText,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                i18n.t('github.sheet_desc'),
                style: TextStyle(fontFamily: 'AnthropicSans', color: secondaryText, fontSize: 12.5, height: 1.45),
              ),
              if (_linkedKind != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _linkedKind == 'pat' ? ExodoPalette.gold : Colors.greenAccent.shade400,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'GitHub · ${_linkedKind == 'pat' ? 'PAT' : 'OAuth'}',
                      style: TextStyle(fontFamily: 'AnthropicSans', fontSize: 11.5, color: secondaryText),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (_result == null) ..._buildForm(i18n, primaryText, secondaryText, deco)
              else ..._buildSuccess(i18n, primaryText, secondaryText),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildForm(
    AppI18n i18n,
    Color primaryText,
    Color secondaryText,
    InputDecoration Function(String hintKey, {bool bad}) deco,
  ) {
    return [
      TextField(
        controller: _repoCtrl,
        style: TextStyle(fontFamily: 'AnthropicSans', fontSize: 13.5, color: primaryText),
        cursorColor: ExodoPalette.gold,
        textInputAction: TextInputAction.next,
        decoration: deco('github.repo_hint', bad: _repoBad),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _pathCtrl,
        style: TextStyle(fontFamily: 'AnthropicSans', fontSize: 13.5, color: primaryText),
        cursorColor: ExodoPalette.gold,
        textInputAction: TextInputAction.next,
        decoration: deco('github.path_hint', bad: _pathBad),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _msgCtrl,
        maxLines: 2,
        minLines: 1,
        style: TextStyle(fontFamily: 'AnthropicSans', fontSize: 13, color: primaryText),
        cursorColor: ExodoPalette.gold,
        decoration: deco('github.msg_hint'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _branchCtrl,
        style: TextStyle(fontFamily: 'AnthropicSans', fontSize: 13.5, color: primaryText),
        cursorColor: ExodoPalette.gold,
        decoration: deco('github.branch_hint', bad: _branchBad),
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _showPatField = !_showPatField),
          icon: Icon(Icons.link_rounded, size: 15, color: secondaryText),
          label: Text(
            i18n.t('github.link_btn'),
            style: TextStyle(fontFamily: 'AnthropicSans', fontSize: 12, color: secondaryText),
          ),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
        ),
      ),
      if (_showPatField) ...[
        const SizedBox(height: 6),
        TextField(
          controller: _patCtrl,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: primaryText),
          cursorColor: ExodoPalette.gold,
          decoration: deco('github.pat_hint'),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.10),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _error!,
            style: const TextStyle(fontFamily: 'AnthropicSans', fontSize: 12, color: Colors.redAccent),
          ),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        height: 46,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: ExodoPalette.gold,
            foregroundColor: const Color(0xFF191919),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _busy ? null : _onCommit,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF191919)),
                )
              : Text(
                  i18n.t('github.commit_btn'),
                  style: const TextStyle(fontFamily: 'AnthropicSans', fontWeight: FontWeight.w700, fontSize: 14),
                ),
        ),
      ),
    ];
  }

  List<Widget> _buildSuccess(
    AppI18n i18n,
    Color primaryText,
    Color secondaryText,
  ) {
    final res = _result!;
    return [
      const SizedBox(height: 6),
      const Center(
        child: Icon(Icons.check_circle_rounded, color: ExodoPalette.gold, size: 44),
      ),
      const SizedBox(height: 10),
      Center(
        child: Text(
          i18n.t('github.success'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'AnthropicSans',
            color: primaryText,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      const SizedBox(height: 14),
      if (res.commitUrl != null) _urlRow(res.commitUrl!, primaryText, secondaryText),
      if (res.fileUrl != null) ...[
        const SizedBox(height: 8),
        _urlRow(res.fileUrl!, primaryText, secondaryText),
      ],
      const SizedBox(height: 18),
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: secondaryText.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(
          i18n.t('ctx.cancel').toUpperCase(),
          style: TextStyle(fontFamily: 'AnthropicSans', color: primaryText, fontWeight: FontWeight.w600),
        ),
      ),
    ];
  }

  Widget _urlRow(String url, Color primaryText, Color secondaryText) {
    final copied = _copiedUrls.contains(url);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFEAE7E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white12
              : Colors.black12,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 14, color: secondaryText),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              url,
              maxLines: 2,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: primaryText),
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              HapticFeedback.selectionClick();
              setState(() => _copiedUrls.add(url));
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 16,
                color: copied ? ExodoPalette.gold : secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



