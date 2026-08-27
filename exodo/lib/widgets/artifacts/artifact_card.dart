import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:provider/provider.dart';

import '../../data/artifacts/artifact.dart';
import '../../screens/artifacts/artifact_fullscreen.dart';
import '../../screens/artifacts/expedientes_screen.dart';
import '../../services/app_state.dart';
import '../../services/expedientes_access_policy.dart';
import '../../services/expedientes_repository.dart';
import '../../l10n/app_i18n.dart';
import '../../theme/exodo_palette.dart';
import '../../widgets/artifacts/github_commit_sheet.dart';

/// Single, cohesive, minimal artifact container.
/// Background: #1E1E1E (Dark) / #F4F2EB (Light) with subtle 1px border.
/// Actions: Single compact minimal row: [ Vista previa ] [ Copiar ] [ Abrir ].
class ArtifactCard extends StatefulWidget {
  final Artifact artifact;
  final VoidCallback? onOpen;

  const ArtifactCard({
    super.key,
    required this.artifact,
    this.onOpen,
  });

  @override
  State<ArtifactCard> createState() => _ArtifactCardState();
}

class _ArtifactCardState extends State<ArtifactCard> {
  bool _isExpanded = false;
  bool _copied = false;
  bool _savedToExpedientes = false;
  bool _savingExpediente = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.artifact.sourceCode));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _preview() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArtifactFullscreen(artifact: widget.artifact),
      ),
    );
  }

  void _open() {
    HapticFeedback.lightImpact();
    if (widget.onOpen != null) {
      widget.onOpen!();
    } else {
      _preview();
    }
  }

  Future<void> _saveToExpedientes() async {
    // [Punto 3] Defensa en profundidad: un invitado jamás persiste un
    // expediente aunque este método sea invocado por cualquier vía.
    if (!canSaveExpediente(isGuestUser: context.read<AppState>().isGuestUser)) {
      HapticFeedback.vibrate();
      return;
    }
    if (_savingExpediente) return;
    final a = widget.artifact;
    setState(() => _savingExpediente = true);

    try {
      String category = 'documento';
      String fileFormat = 'md';

      if (a.kind == ArtifactKind.table) {
        category = 'tabla';
        fileFormat = 'xlsx';
      } else if (a.kind == ArtifactKind.html || a.kind == ArtifactKind.react) {
        category = 'interactivo';
        fileFormat = 'html';
      } else if (a.kind == ArtifactKind.svg) {
        category = 'interactivo';
        fileFormat = 'svg';
      }

      final title = (a.title != null && a.title!.trim().isNotEmpty)
          ? a.title!.trim()
          : (a.language.isNotEmpty
              ? 'Artefacto ${a.language.toUpperCase()}'
              : 'Expediente Éxodo');

      final saved = await ExpedientesRepository.instance.createExpediente(
        title: title,
        category: category,
        fileFormat: fileFormat,
        contentPayload: a.sourceCode,
        chatId: a.conversationId.isNotEmpty ? a.conversationId : null,
        metadata: {
          ...a.meta,
          'message_id': a.messageId,
          'conversation_id': a.conversationId,
        },
      );

      if (!mounted) return;
      // [Punto 3] El repositorio devuelve null para invitados: nunca marcar
      // "Guardado" ni navegar al módulo si no se persistió realmente.
      if (saved != null) {
        HapticFeedback.lightImpact();
        setState(() => _savedToExpedientes = true);
      } else {
        HapticFeedback.vibrate();
      }
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.vibrate();
    } finally {
      if (mounted) setState(() => _savingExpediente = false);
    }
  }

  /// [Punto 5] Abre el modal de consentimiento GitHub para este artefacto.
  void _commitToGitHub() {
    if (!canSaveExpediente(isGuestUser: context.read<AppState>().isGuestUser)) {
      HapticFeedback.vibrate();
      return;
    }
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => GithubCommitSheet(artifact: widget.artifact),
    );
  }

  @override
  Widget build(BuildContext context) {
    const cardBg = Color(0xFF1E1E1E);
    const borderColor = Color(0xFF2E2E2E);

    // [Punto 3] El guardado de expedientes es exclusivo de cuentas; para
    // invitados la acción desaparece por completo de la fila de opciones.
    final canSave =
        canSaveExpediente(isGuestUser: context.watch<AppState>().isGuestUser);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: borderColor, width: 1.0),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(
            artifact: widget.artifact,
            isDark: true,
            borderColor: borderColor,
            isExpanded: _isExpanded,
            onToggleExpand: () => setState(() => _isExpanded = !_isExpanded),
          ),
          if (widget.artifact.isTabular)
            _TablePreview(artifact: widget.artifact, isDark: true, isExpanded: _isExpanded)
          else
            _CodePreview(artifact: widget.artifact, isDark: true, isExpanded: _isExpanded),
          _Actions(
            artifact: widget.artifact,
            isDark: true,
            borderColor: borderColor,
            copied: _copied,
            showSaveAction: canSave,
            showGithubAction: canSave,
            onCommitToGitHub: _commitToGitHub,
            savedToExpedientes: _savedToExpedientes,
            savingExpediente: _savingExpediente,
            onPreview: _preview,
            onCopy: _copy,
            onOpen: _open,
            onSaveToExpedientes: _saveToExpedientes,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Artifact artifact;
  final bool isDark;
  final Color borderColor;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const _Header({
    required this.artifact,
    required this.isDark,
    required this.borderColor,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final title = artifact.title?.trim();
    final hasDistinctTitle = title != null &&
        title.isNotEmpty &&
        title.toLowerCase() != artifact.language.toLowerCase() &&
        title.toLowerCase() != artifact.kind.name.toLowerCase() &&
        title.toLowerCase() != 'code';

    final String? secondaryLabel = hasDistinctTitle
        ? title
        : (artifact.kind == ArtifactKind.code &&
                artifact.language.isNotEmpty &&
                artifact.language.toLowerCase() != 'code' &&
                artifact.language.toLowerCase() != 'text'
            ? artifact.language.toUpperCase()
            : null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: Row(
        children: [
          _KindBadge(kind: artifact.kind),
          if (secondaryLabel != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                secondaryLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: Color(0xFFF5F2EB),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          const Spacer(),
          Text(
            _summary(artifact.sourceCode),
            style: const TextStyle(
              fontFamily: 'AnthropicSans',
              color: Color(0xFF8E8E93),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _summary(String src) {
    final lines = src.split('\n').length;
    final chars = src.length;
    return '$lines líneas · $chars caracteres';
  }
}

class _KindBadge extends StatelessWidget {
  final ArtifactKind kind;

  const _KindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      ArtifactKind.html    => 'HTML',
      ArtifactKind.svg     => 'SVG',
      ArtifactKind.mermaid => 'Mermaid',
      ArtifactKind.react   => 'JSX',
      ArtifactKind.vue     => 'Vue',
      ArtifactKind.code    => 'Code',
      ArtifactKind.table   => 'Tabla',
      ArtifactKind.json    => 'JSON',
      ArtifactKind.latex   => 'LaTeX',
      ArtifactKind.diagram => 'Diagrama',
    };

    const brandAmber = Color(0xFFD4A843);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: brandAmber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: brandAmber.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'AnthropicSans',
          color: brandAmber,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _CodePreview extends StatelessWidget {
  final Artifact artifact;
  final bool isDark;
  final bool isExpanded;

  const _CodePreview({
    required this.artifact,
    required this.isDark,
    required this.isExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final lines = artifact.sourceCode.split('\n');
    final src = isExpanded ? artifact.sourceCode : lines.take(8).join('\n');
    final lang = switch (artifact.language.toLowerCase()) {
      'html' || 'htm' || 'svg' || 'xml' => 'xml',
      'js' || 'jsx' || 'react' => 'javascript',
      'ts' || 'tsx' => 'typescript',
      'py' || 'python' => 'python',
      'sh' || 'bash' || 'zsh' => 'bash',
      'yml' || 'yaml' => 'yaml',
      'json' => 'json',
      'dart' => 'dart',
      'css' => 'css',
      'sql' => 'sql',
      'markdown' || 'md' => 'markdown',
      _ => 'plaintext',
    };

    // Paleta de sintaxis Éxodo Brand: Ámbar, Arena, Terracota suave y Tiza
    final theme = <String, TextStyle>{
      'root': const TextStyle(
        backgroundColor: Colors.transparent,
        color: Color(0xFFF5F2EB),
      ),
      'tag': const TextStyle(color: Color(0xFFD4A843), fontWeight: FontWeight.w600),
      'name': const TextStyle(color: Color(0xFFD4A843), fontWeight: FontWeight.w600),
      'keyword': const TextStyle(color: Color(0xFFD4A843), fontWeight: FontWeight.w600),
      'selector-tag': const TextStyle(color: Color(0xFFD4A843), fontWeight: FontWeight.w600),
      'attr': const TextStyle(color: Color(0xFFE5C07B)),
      'attribute': const TextStyle(color: Color(0xFFE5C07B)),
      'variable': const TextStyle(color: Color(0xFFE5C07B)),
      'string': const TextStyle(color: Color(0xFFCE9178)),
      'value': const TextStyle(color: Color(0xFFCE9178)),
      'number': const TextStyle(color: Color(0xFFD19A66)),
      'literal': const TextStyle(color: Color(0xFFD19A66)),
      'comment': const TextStyle(color: Color(0xFF8E8E93), fontStyle: FontStyle.italic),
      'quote': const TextStyle(color: Color(0xFF8E8E93), fontStyle: FontStyle.italic),
      'symbol': const TextStyle(color: Color(0xFF61AFEF)),
      'bullet': const TextStyle(color: Color(0xFF61AFEF)),
      'built_in': const TextStyle(color: Color(0xFFE5C07B)),
      'title': const TextStyle(color: Color(0xFF61AFEF)),
      'section': const TextStyle(color: Color(0xFFD4A843), fontWeight: FontWeight.bold),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicWidth(
          child: HighlightView(
            src,
            language: lang,
            theme: theme,
            padding: EdgeInsets.zero,
            textStyle: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
              color: Color(0xFFF5F2EB),
            ),
          ),
        ),
      ),
    );
  }
}

class _TablePreview extends StatelessWidget {
  final Artifact artifact;
  final bool isDark;
  final bool isExpanded;

  const _TablePreview({
    required this.artifact,
    required this.isDark,
    required this.isExpanded,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final headers = (artifact.meta['headers'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final rawRows = (artifact.meta['rows'] as List?) ?? [];
      final rows = rawRows.map((r) => (r as List).map((e) => e.toString()).toList()).toList();
      final displayedRows = isExpanded ? rows : rows.take(5).toList();

      final textColor = isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919);
      final borderColor = isDark ? const Color(0xFF2E2E2E) : const Color(0x14000000);
      final headerBg = isDark ? const Color(0xFF262626) : const Color(0xFFE8E5DD);

      if (headers.isEmpty && rows.isEmpty) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicWidth(
              child: Text(
                artifact.sourceCode,
                style: TextStyle(
                  color: textColor,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
      }

      int maxCols = headers.length;
      for (final r in displayedRows) {
        if (r.length > maxCols) maxCols = r.length;
      }
      if (maxCols == 0) maxCols = 1;

      final tableRows = <TableRow>[];
      if (headers.isNotEmpty) {
        final normalizedHeaders = List<String>.from(headers);
        while (normalizedHeaders.length < maxCols) {
          normalizedHeaders.add('');
        }
        tableRows.add(
          TableRow(
            decoration: BoxDecoration(
              color: headerBg,
            ),
            children: normalizedHeaders
                .map(
                  (h) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Text(
                      h,
                      style: TextStyle(
                        fontFamily: 'AnthropicSans',
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      }

      for (final row in displayedRows) {
        final normalizedRow = List<String>.from(row);
        while (normalizedRow.length < maxCols) {
          normalizedRow.add('');
        }
        tableRows.add(
          TableRow(
            children: normalizedRow
                .map(
                  (cell) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Text(
                      cell,
                      style: TextStyle(
                        fontFamily: 'AnthropicSans',
                        color: textColor,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      }

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(10),
        child: IntrinsicWidth(
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder.all(color: borderColor, width: 0.8, borderRadius: BorderRadius.circular(6)),
            children: tableRows,
          ),
        ),
      );
    } catch (e) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            artifact.sourceCode,
            style: TextStyle(
              color: isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
      );
    }
  }
}

class _Actions extends StatelessWidget {
  final Artifact artifact;
  final bool isDark;
  final Color borderColor;
  final bool copied;

  /// [Punto 3] false para invitados: el botón "Guardar en Expedientes" no
  /// se dibuja (tampoco su separador), evitando cualquier acceso al módulo.
   final bool showSaveAction;
  final bool savedToExpedientes;
  final bool savingExpediente;

  /// [Punto 5] false para invitados: la acción "Commitear a GitHub" no se
  /// dibuja (mismo criterio de ocultación que Guardar en Expedientes).
  final bool showGithubAction;
  final VoidCallback onCommitToGitHub;
  final VoidCallback onPreview;
  final VoidCallback onCopy;
  final VoidCallback onOpen;
  final VoidCallback onSaveToExpedientes;

  const _Actions({
    required this.artifact,
    required this.isDark,
    required this.borderColor,
    required this.copied,
    required this.showSaveAction,
    required this.showGithubAction,
    required this.onCommitToGitHub,
    required this.savedToExpedientes,
    required this.savingExpediente,
    required this.onPreview,
    required this.onCopy,
    required this.onOpen,
    required this.onSaveToExpedientes,
  });

  @override
  Widget build(BuildContext context) {
    const actionColor = Color(0xFF8E8E93); // Muted gray #8E8E93

    Widget actionBtn({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color color = actionColor,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            actionBtn(
              icon: Icons.visibility_outlined,
              label: AppI18n.of(context).t('artifacts.action_preview'),
              onTap: onPreview,
            ),
            if (showSaveAction) ...[
              const SizedBox(width: 4),
              actionBtn(
                icon: savedToExpedientes
                    ? Icons.check_circle_rounded
                    : (savingExpediente
                        ? Icons.hourglass_top_rounded
                        : Icons.bookmark_add_outlined),
                label: savedToExpedientes
                    ? AppI18n.of(context).t('artifacts.action_saved')
                    : (savingExpediente
                        ? AppI18n.of(context).t('artifacts.action_saving')
                        : AppI18n.of(context).t('artifacts.action_save')),
                onTap: savedToExpedientes
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ExpedientesScreen(),
                          ),
                        );
                      }
                    : onSaveToExpedientes,
                color: savedToExpedientes
                    ? ExodoPalette.gold
                    : (savingExpediente ? ExodoPalette.gold : actionColor),
              ),
            ],
            if (showGithubAction) ...[
              const SizedBox(width: 4),
              actionBtn(
                icon: Icons.account_tree_outlined,
                label: AppI18n.of(context).t('github.commit_chip'),
                onTap: onCommitToGitHub,
              ),
            ],
            const SizedBox(width: 4),
            actionBtn(
              icon: copied ? Icons.check_rounded : Icons.copy_rounded,
              label: copied
                  ? AppI18n.of(context).t('code.copied')
                  : AppI18n.of(context).t('act.copy'),
              onTap: onCopy,
              color: copied ? ExodoPalette.gold : actionColor,
            ),
            const SizedBox(width: 4),
            actionBtn(
              icon: Icons.open_in_new_rounded,
              label: AppI18n.of(context).t('artifacts.open_fullscreen'),
              onTap: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}
