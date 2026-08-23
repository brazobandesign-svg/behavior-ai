import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/artifacts/artifact.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../services/artifacts_service.dart';
import '../../services/expedientes_repository.dart';
import '../../services/export/exporters.dart';
import '../../theme/exodo_palette.dart';

import '../../templates/sandbox_template.dart';

// Re-export for external modules (e.g. exporters.dart)
export '../../templates/sandbox_template.dart' show SandboxTemplate;

// ═══════════════════════════════════════════════════════════════════════════════
// 2. ARTIFACT FULLSCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class ArtifactFullscreen extends StatefulWidget {
  final Artifact artifact;
  const ArtifactFullscreen({super.key, required this.artifact});

  @override
  State<ArtifactFullscreen> createState() => _ArtifactFullscreenState();
}

class _ArtifactFullscreenState extends State<ArtifactFullscreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final a = widget.artifact;
    await Clipboard.setData(ClipboardData(text: a.sourceCode));
    if (!mounted) return;
    HapticFeedback.lightImpact();
  }

  Future<void> _shareSource() async {
    final a = widget.artifact;
    // ignore: deprecated_member_use
    await Share.share(
      a.sourceCode,
      subject: a.title ?? 'Artefacto Éxodo (${a.language})',
    );
  }

  bool _publishing = false;

  Future<void> _shareWebLink() async {
    if (_publishing) return;
    setState(() => _publishing = true);
    HapticFeedback.lightImpact();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: ExodoPalette.gold),
            ),
            SizedBox(width: 12),
            Text('Generando enlace web público...'),
          ],
        ),
        duration: Duration(seconds: 4),
      ),
    );

    try {
      final a = widget.artifact;
      final url = await ArtifactsService.publishArtifact(a);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (url != null && url.isNotEmpty) {
        await ShareService.instance.shareText(
          'Consulta este recurso en Éxodo: $url',
          subject: a.title ?? 'Artefacto Éxodo',
        );
      } else {
        await _shareSource();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al compartir: $e'),
          backgroundColor: ExodoPalette.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  bool _savingExpediente = false;

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

      final expediente = await ExpedientesRepository.instance.createExpediente(
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

      if (expediente != null) {
        HapticFeedback.lightImpact();
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

  Future<void> _navigateToConversation() async {
    final convId = widget.artifact.conversationId;
    if (convId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Conversación original no disponible.'),
          backgroundColor: const Color(0xFF252525),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final state = context.read<AppState>();
    Conversation? targetConv =
        state.conversations.where((c) => c.id == convId).firstOrNull;
    targetConv ??= Conversation(
      id: convId,
      userId: state.profile?.id ?? '',
      title: widget.artifact.title ?? 'Conversación',
      createdAt: widget.artifact.detectedAt,
      updatedAt: widget.artifact.updatedAt,
    );
    await state.selectConversation(targetConv);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _openExportSheet() async {
    final a = widget.artifact;
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF191919) : Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ExportSheet(artifact: a),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.artifact;
    final title = a.title?.trim();
    final hasDistinctTitle = title != null &&
        title.isNotEmpty &&
        title.toLowerCase() != a.language.toLowerCase() &&
        title.toLowerCase() != a.kind.name.toLowerCase() &&
        title.toLowerCase() != 'code' &&
        title.toLowerCase() != 'código';

    final displayTitle = hasDistinctTitle
        ? title
        : (a.kind == ArtifactKind.code &&
                a.language.isNotEmpty &&
                a.language.toLowerCase() != 'code'
            ? a.language.toUpperCase()
            : a.kind.name.toUpperCase());

    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      appBar: AppBar(
        backgroundColor: const Color(0xFF191919),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFFF5F2EB)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          displayTitle,
          style: const TextStyle(
            fontFamily: 'AnthropicSans',
            color: Color(0xFFF5F2EB),
            fontWeight: FontWeight.w600,
            fontSize: 17,
            letterSpacing: -0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.artifact.conversationId.isNotEmpty)
            IconButton(
              tooltip: 'Ir a la conversación',
              icon: const Icon(Icons.forum_outlined, color: Color(0xFF8E8E93)),
              onPressed: _navigateToConversation,
            ),
          IconButton(
            tooltip: 'Guardar en Expedientes',
            icon: _savingExpediente
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ExodoPalette.gold,
                    ),
                  )
                : const Icon(Icons.bookmark_add_outlined, color: Color(0xFF8E8E93)),
            onPressed: _savingExpediente ? null : _saveToExpedientes,
          ),
          IconButton(
            tooltip: 'Copiar código',
            icon: const Icon(Icons.copy_rounded, color: Color(0xFF8E8E93)),
            onPressed: _copy,
          ),
          IconButton(
            tooltip: 'Compartir enlace web',
            icon: const Icon(Icons.share_outlined, color: Color(0xFF8E8E93)),
            onPressed: _shareWebLink,
          ),
          IconButton(
            tooltip: 'Exportar archivo',
            icon: const Icon(Icons.ios_share_rounded, color: Color(0xFF8E8E93)),
            onPressed: _openExportSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: const Color(0xFFF5F2EB),
          indicatorWeight: 2,
          labelColor: const Color(0xFFF5F2EB),
          unselectedLabelColor: const Color(0xFF8E8E93),
          labelStyle: const TextStyle(fontFamily: 'AnthropicSans', fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: 0.4),
          tabs: const [
            Tab(icon: Icon(Icons.visibility_rounded, size: 18), text: 'VISTA PREVIA'),
            Tab(icon: Icon(Icons.code_rounded, size: 18), text: 'CÓDIGO'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          a.isExecutable
              ? _SandboxWebView(artifact: a)
              : _StaticViewer(artifact: a),
          _CodeView(artifact: a),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3. SANDBOX WEBVIEW
// ═══════════════════════════════════════════════════════════════════════════════

class _SandboxWebView extends StatefulWidget {
  final Artifact artifact;
  const _SandboxWebView({required this.artifact});

  @override
  State<_SandboxWebView> createState() => _SandboxWebViewState();
}

class _SandboxWebViewState extends State<_SandboxWebView> {
  InAppWebViewController? _controller;
  bool _loading = true;

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SandboxWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artifact.sourceCode != widget.artifact.sourceCode ||
        oldWidget.artifact.kind != widget.artifact.kind) {
      final cleanHtml = SandboxTemplate.wrap(
        kind: widget.artifact.kind,
        source: widget.artifact.sourceCode,
      );
      _controller?.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(
            Uri.dataFromString(
              cleanHtml,
              mimeType: 'text/html',
              encoding: Encoding.getByName('utf-8'),
            ).toString(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.artifact;
    final cleanHtml = SandboxTemplate.wrap(kind: a.kind, source: a.sourceCode);

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: InAppWebView(
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                supportZoom: false,
                useWideViewPort: true,
                loadWithOverviewMode: true,
                transparentBackground: true,
                allowFileAccess: true,
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
                controller.loadUrl(
                  urlRequest: URLRequest(
                    url: WebUri(
                      Uri.dataFromString(
                        cleanHtml,
                        mimeType: 'text/html',
                        encoding: Encoding.getByName('utf-8'),
                      ).toString(),
                    ),
                  ),
                );
              },
              onLoadStart: (controller, url) {
                if (mounted) setState(() => _loading = true);
              },
              onLoadStop: (controller, url) async {
                if (mounted) setState(() => _loading = false);
              },
              onReceivedError: (controller, request, error) {
                if (mounted) setState(() => _loading = false);
              },
              onConsoleMessage: (controller, consoleMessage) {
                if (kDebugMode) {
                  debugPrint('[Sandbox ${a.kind.name}] ${consoleMessage.message}');
                }
              },
            ),
          ),
          if (_loading)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ExodoPalette.gold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 4. STATIC VIEWER & TABLE VIEWER
// ═══════════════════════════════════════════════════════════════════════════════

class _StaticViewer extends StatelessWidget {
  final Artifact artifact;
  const _StaticViewer({required this.artifact});

  @override
  Widget build(BuildContext context) {
    if (artifact.kind == ArtifactKind.table) {
      return _TableDataViewer(artifact: artifact);
    }
    if (artifact.kind == ArtifactKind.json) {
      return _CodeView(artifact: artifact);
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Este artefacto no tiene una vista previa interactiva.\nAbre la pestaña Código para inspeccionarlo.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ExodoPalette.textMuted,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _TableDataViewer extends StatelessWidget {
  final Artifact artifact;
  const _TableDataViewer({required this.artifact});

  @override
  Widget build(BuildContext context) {
    final meta = artifact.meta;
    final rawHeaders = meta['headers'];
    final rawRows = meta['rows'];

    final headers = (rawHeaders is List)
        ? rawHeaders.map((e) => e.toString()).toList(growable: false)
        : <String>[];
    final rows = (rawRows is List)
        ? rawRows
            .whereType<List>()
            .map((r) => r.map((c) => c.toString()).toList(growable: true))
            .toList(growable: false)
        : <List<String>>[];

    if (headers.isEmpty && rows.isEmpty) {
      return const Center(
        child: Text(
          'Tabla sin datos detectables.',
          style: TextStyle(color: ExodoPalette.textMuted),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: const TextStyle(
            fontFamily: 'AnthropicSans',
            color: Color(0xFFF5F2EB),
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.4,
          ),
          dataTextStyle: const TextStyle(
            fontFamily: 'AnthropicSans',
            color: ExodoPalette.textOnDark,
            fontSize: 12.5,
          ),
          headingRowColor: WidgetStateProperty.all(ExodoPalette.inkRaised),
          dataRowColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return ExodoPalette.inkLine.withValues(alpha: 0.2);
            }
            return null;
          }),
          border: TableBorder.all(
            color: ExodoPalette.inkLine,
            width: 0.5,
            borderRadius: BorderRadius.circular(6),
          ),
          columnSpacing: 22,
          horizontalMargin: 14,
          columns: [
            for (final h in headers) DataColumn(label: Text(h.toUpperCase())),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                cells: [
                  for (final c in r) DataCell(Text(c)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 5. CODE VIEW
// ═══════════════════════════════════════════════════════════════════════════════

class _CodeView extends StatelessWidget {
  final Artifact artifact;
  const _CodeView({required this.artifact});

  @override
  Widget build(BuildContext context) {
    String lang = _mapLanguage(artifact.language);
    if (artifact.kind == ArtifactKind.html || artifact.kind == ArtifactKind.svg) {
      lang = 'xml';
    }
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
      color: ExodoPalette.inkDeep,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: HighlightView(
              artifact.sourceCode,
              language: lang,
              theme: theme,
              padding: EdgeInsets.zero,
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.5,
                letterSpacing: 0,
                color: Color(0xFFF5F2EB),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _mapLanguage(String raw) {
    final l = raw.toLowerCase();
    switch (l) {
      case 'html':
      case 'htm':
      case 'svg':
      case 'xml':
        return 'xml';
      case 'js':
      case 'jsx':
      case 'mjs':
        return 'javascript';
      case 'ts':
      case 'tsx':
        return 'typescript';
      case 'py':
        return 'python';
      case 'sh':
      case 'bash':
      case 'zsh':
        return 'bash';
      case 'yml':
      case 'yaml':
        return 'yaml';
      case 'md':
      case 'markdown':
        return 'markdown';
      case 'kt':
        return 'kotlin';
      case 'cpp':
      case 'cxx':
        return 'cpp';
      case 'cs':
        return 'cs';
      case 'rb':
        return 'ruby';
      case 'rs':
        return 'rust';
      case 'go':
        return 'go';
      case 'java':
        return 'java';
      case 'swift':
        return 'swift';
      case 'dart':
        return 'dart';
      case 'sql':
        return 'sql';
      case 'json':
        return 'json';
      default:
        return l.isEmpty ? 'plaintext' : l;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 6. EXPORT SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class ExportSheet extends StatefulWidget {
  final Artifact artifact;
  const ExportSheet({super.key, required this.artifact});

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<File?> Function() task, String label) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await task();
      if (!mounted) return;
      if (file == null) {
        setState(() => _error = 'Esta opción no aplica a este artefacto.');
        return;
      }
      Navigator.of(context).pop();
      await ShareService.instance.shareFile(
        file,
        text: widget.artifact.title ?? 'Artefacto Éxodo',
        subject: widget.artifact.title,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Error al exportar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishWebLink() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await ArtifactsService.publishArtifact(widget.artifact);
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() => _error = 'No se pudo generar el enlace web.');
        return;
      }
      Navigator.of(context).pop();
      await ShareService.instance.shareText(
        'Consulta este recurso en Éxodo: $url',
        subject: widget.artifact.title ?? 'Artefacto Éxodo',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Error al publicar enlace: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.artifact;
    final isTabular = a.kind == ArtifactKind.table;
    final isExecutable = a.isExecutable;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919);
    final secondaryTextColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.ios_share_rounded, color: primaryTextColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Exportar artefacto',
                  style: TextStyle(
                    fontFamily: 'AnthropicSans',
                    color: primaryTextColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Elige un formato. El archivo se generará y se abrirá el menú de compartir.',
              style: TextStyle(
                fontFamily: 'AnthropicSans',
                color: secondaryTextColor,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _ExportTile(
              icon: Icons.link_rounded,
              label: 'Compartir enlace web',
              description: 'Genera una URL pública interactiva en exodo.app',
              onTap: _publishWebLink,
              enabled: !_busy,
            ),
            _ExportTile(
              icon: Icons.picture_as_pdf_rounded,
              label: 'PDF',
              description: 'Maquetado limpio para lectura e impresión',
              onTap: () => _run(() => PdfExporter().exportArtifact(a), 'PDF'),
              enabled: !_busy,
            ),
            _ExportTile(
              icon: Icons.description_rounded,
              label: 'DOCX',
              description: 'Documento Word con títulos y estructura nativa',
              onTap: () => _run(() => DocxExporter().exportArtifact(a), 'DOCX'),
              enabled: !_busy,
            ),
            if (isTabular)
              _ExportTile(
                icon: Icons.table_view_rounded,
                label: 'XLSX',
                description: 'Hoja de cálculo con celdas formateadas',
                onTap: () => _run(() => XlsxExporter().exportArtifact(a), 'XLSX'),
                enabled: !_busy,
              ),
            if (isExecutable)
              _ExportTile(
                icon: Icons.code_rounded,
                label: 'HTML standalone',
                description: 'Archivo HTML independiente sanitizado',
                onTap: () => _run(() => ExportRepositoryHelpers.exportStandaloneHtml(a), 'HTML'),
                enabled: !_busy,
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ExodoPalette.danger.withValues(alpha: 0.12),
                  border: Border.all(color: ExodoPalette.danger),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'AnthropicSans',
                    color: ExodoPalette.danger,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(
                'CANCELAR',
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: secondaryTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool enabled;

  const _ExportTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919);
    final secondaryTextColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled ? primaryTextColor : secondaryTextColor,
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'AnthropicSans',
                        color: enabled ? primaryTextColor : secondaryTextColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        letterSpacing: 0.2,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontFamily: 'AnthropicSans',
                        color: secondaryTextColor,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!enabled)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8E8E93)),
                )
              else
                Icon(Icons.chevron_right_rounded, color: secondaryTextColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
