import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import '../../data/artifacts/artifact.dart';
import '../../screens/artifacts/artifact_fullscreen.dart';
import '../../screens/artifacts/expedientes_screen.dart';
import '../../services/expedientes_repository.dart';
import '../../theme/exodo_palette.dart';

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

      await ExpedientesRepository.instance.createExpediente(
        title: title,
        category: category,
        fileFormat: fileFormat,
        contentPayload: a.sourceCode,
        metadata: a.meta,
      );

      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _savedToExpedientes = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFFF5F2EB), size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Guardado en tus Expedientes')),
            ],
          ),
          backgroundColor: ExodoPalette.inkRaised,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'VER',
            textColor: ExodoPalette.gold,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExpedientesScreen()),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: ExodoPalette.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingExpediente = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF4F2EB);
    final borderColor = isDark ? const Color(0xFF2E2E2E) : const Color(0x14000000); // subtle 1px rgba(0,0,0,0.08)

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
            isDark: isDark,
            borderColor: borderColor,
            isExpanded: _isExpanded,
            onToggleExpand: () => setState(() => _isExpanded = !_isExpanded),
          ),
          if (widget.artifact.isTabular)
            _TablePreview(artifact: widget.artifact, isDark: isDark, isExpanded: _isExpanded)
          else
            _CodePreview(artifact: widget.artifact, isDark: isDark, isExpanded: _isExpanded),
          _Actions(
            artifact: widget.artifact,
            isDark: isDark,
            borderColor: borderColor,
            copied: _copied,
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
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919),
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
            style: TextStyle(
              fontFamily: 'AnthropicSans',
              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF8A8279),
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
    final (label, color) = switch (kind) {
      ArtifactKind.html    => ('HTML', const Color(0xFFE44D26)),
      ArtifactKind.svg     => ('SVG', const Color(0xFFFFB13B)),
      ArtifactKind.mermaid => ('Mermaid', const Color(0xFF00C853)),
      ArtifactKind.react   => ('JSX', const Color(0xFF61DAFB)),
      ArtifactKind.vue     => ('Vue', const Color(0xFF42B883)),
      ArtifactKind.code    => ('Code', const Color(0xFF8E8E93)),
      ArtifactKind.table   => ('Tabla', const Color(0xFF8E8E93)),
      ArtifactKind.json    => ('JSON', const Color(0xFFFF9800)),
      ArtifactKind.latex   => ('LaTeX', const Color(0xFF8E8E93)),
      ArtifactKind.diagram => ('Diagrama', const Color(0xFF8E8E93)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'AnthropicSans',
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
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

    final theme = Map<String, TextStyle>.from(atomOneDarkTheme);
    theme['root'] = const TextStyle(
      backgroundColor: Colors.transparent,
      color: Color(0xFFABB2BF),
    );

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
            textStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
              color: isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919),
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
  final bool savedToExpedientes;
  final bool savingExpediente;
  final VoidCallback onPreview;
  final VoidCallback onCopy;
  final VoidCallback onOpen;
  final VoidCallback onSaveToExpedientes;

  const _Actions({
    required this.artifact,
    required this.isDark,
    required this.borderColor,
    required this.copied,
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
              label: 'Vista previa',
              onTap: onPreview,
            ),
            const SizedBox(width: 4),
            actionBtn(
              icon: savedToExpedientes
                  ? Icons.check_circle_rounded
                  : (savingExpediente
                      ? Icons.hourglass_top_rounded
                      : Icons.bookmark_add_outlined),
              label: savedToExpedientes
                  ? 'Guardado'
                  : (savingExpediente
                      ? 'Guardando...'
                      : 'Guardar en Expedientes'),
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
                  ? const Color(0xFF34C759)
                  : (savingExpediente ? ExodoPalette.gold : actionColor),
            ),
            const SizedBox(width: 4),
            actionBtn(
              icon: copied ? Icons.check_rounded : Icons.copy_rounded,
              label: copied ? 'Copiado' : 'Copiar',
              onTap: onCopy,
              color: copied ? Colors.green : actionColor,
            ),
            const SizedBox(width: 4),
            actionBtn(
              icon: Icons.open_in_new_rounded,
              label: 'Abrir',
              onTap: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}
