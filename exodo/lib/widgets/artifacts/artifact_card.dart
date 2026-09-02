import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../../data/artifacts/artifact.dart';
import '../../screens/artifacts/artifact_fullscreen.dart';
import '../../screens/artifacts/expedientes_screen.dart';
import '../../services/app_state.dart';
import '../../services/expedientes_access_policy.dart';
import '../../services/expedientes_repository.dart';
import '../../l10n/app_i18n.dart';
import '../../theme/exodo_palette.dart';
import '../../theme/exodo_theme.dart';
import '../../widgets/artifacts/github_commit_sheet.dart';
import '../chat/image_generating_placeholder.dart';

/// Single, cohesive, minimal artifact container.
/// Background: #1E1E1E (Dark) / #F4F2EB (Light) with subtle 1px border.
/// Actions: Single compact minimal row: [ Vista previa ] [ Copiar ] [ Abrir ].
///
/// Artefactos ejecutables (HTML/SVG/Mermaid): renderizan una vista previa
/// viva INLINE dentro del chat (mismo sandbox que pantalla completa), con
/// toggle Vista/Código en la cabecera. Durante el streaming se muestra el
/// código y, al terminar, la tarjeta conmuta sola a la vista renderizada.
class ArtifactCard extends StatefulWidget {
  final Artifact artifact;
  final VoidCallback? onOpen;

  /// true mientras el mensaje sigue generándose: aplaza la vista previa
  /// inline hasta que el HTML esté completo (evita WebViews recargando).
  final bool isStreaming;

  /// Tema del chat: true = fondo claro (cromo exterior blanco, código oscuro).
  final bool isLight;

  const ArtifactCard({
    super.key,
    required this.artifact,
    this.onOpen,
    this.isStreaming = false,
    this.isLight = false,
  });

  @override
  State<ArtifactCard> createState() => _ArtifactCardState();
}

class _ArtifactCardState extends State<ArtifactCard> {
  bool _isExpanded = false;
  bool _copied = false;
  bool _savedToExpedientes = false;
  bool _savingExpediente = false;

  /// Si el usuario toca el toggle durante streaming, puede alternar a ver el código.
  bool _peekCodeDuringStreaming = false;

  /// Vista por defecto: render viva para ejecutables completos.
  late bool _viewPreview =
      widget.artifact.isExecutable && !widget.isStreaming;

  @override
  void didUpdateWidget(covariant ArtifactCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fin del streaming: primera vez que el HTML está completo → render viva.
    if (oldWidget.isStreaming && !widget.isStreaming) {
      if (widget.artifact.isExecutable && !_viewPreview) {
        setState(() {
          _viewPreview = true;
          _peekCodeDuringStreaming = false;
        });
      }
    }
  }

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
    // Cromo exterior adaptativo al tema del chat: blanco puro en claro,
    // grafito en oscuro. El área de código permanece SIEMPRE oscura.
    final cardBg = widget.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1E1E1E);
    final borderColor =
        widget.isLight ? const Color(0x1F000000) : const Color(0xFF2E2E2E);

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
            isDark: !widget.isLight,
            borderColor: borderColor,
            isExpanded: _isExpanded,
            isStreaming: widget.isStreaming,
            showPreviewToggle: widget.artifact.isExecutable,
            previewActive: widget.isStreaming
                ? !_peekCodeDuringStreaming
                : _viewPreview,
            onTogglePreview: widget.artifact.isExecutable
                ? () {
                    HapticFeedback.lightImpact();
                    if (widget.isStreaming) {
                      setState(() =>
                          _peekCodeDuringStreaming = !_peekCodeDuringStreaming);
                    } else {
                      setState(() => _viewPreview = !_viewPreview);
                    }
                  }
                : null,
            onToggleExpand: () => setState(() => _isExpanded = !_isExpanded),
          ),
          if (widget.artifact.isTabular)
            _TablePreview(
              artifact: widget.artifact,
              isDark: !widget.isLight,
              isExpanded: _isExpanded,
            )
          else if (widget.isStreaming &&
              widget.artifact.isExecutable &&
              !_peekCodeDuringStreaming)
            _ArtifactGeneratingShimmer(
              isLight: widget.isLight,
              kind: widget.artifact.kind,
            )
          else if (_viewPreview && widget.artifact.isExecutable)
            _InlineSandboxPreview(
              artifact: widget.artifact,
              isLight: widget.isLight,
            )
          else
            _CodePreview(
              artifact: widget.artifact,
              isDark: !widget.isLight,
              isExpanded: _isExpanded,
            ),
          _Actions(
            artifact: widget.artifact,
            isDark: !widget.isLight,
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
  final bool isStreaming;
  final bool showPreviewToggle;
  final bool previewActive;
  final VoidCallback? onTogglePreview;
  final VoidCallback onToggleExpand;

  const _Header({
    required this.artifact,
    required this.isDark,
    required this.borderColor,
    required this.isExpanded,
    this.isStreaming = false,
    this.showPreviewToggle = false,
    this.previewActive = false,
    this.onTogglePreview,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919);
    const mutedColor = Color(0xFF8E8E93);

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
          _KindBadge(kind: artifact.kind, isDark: isDark),
          if (secondaryLabel != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                secondaryLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: titleColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (isStreaming) ...[
            _GeneratingBadge(isDark: isDark),
            const SizedBox(width: 8),
          ],
          if (showPreviewToggle) ...[
            InkWell(
              onTap: onTogglePreview,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  previewActive ? Icons.code_rounded : Icons.visibility_outlined,
                  size: 16,
                  color: previewActive
                      ? (isDark ? const Color(0xFFD4A843) : const Color(0xFF8A6A10))
                      : mutedColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  final ArtifactKind kind;
  final bool isDark;

  const _KindBadge({required this.kind, this.isDark = true});

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
    // Sobre cromo blanco el ámbar puro pierde contraste: se oscurece.
    final amberText = isDark ? brandAmber : const Color(0xFF8A6A10);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: brandAmber.withValues(alpha: isDark ? 0.14 : 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: amberText.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'AnthropicSans',
          color: amberText,
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
      // El código vive SIEMPRE en bloque oscuro, incluso con cromo blanco.
      color: const Color(0xFF1E1E1E),
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

/// Vista previa viva INLINE del artefacto dentro del chat: mismo sandbox
/// (CSP + polyfill DOM) y mismos ajustes de seguridad que ArtifactFullscreen,
/// pero en altura fija para convivir con el scroll del chat.
class _InlineSandboxPreview extends StatefulWidget {
  final Artifact artifact;
  final bool isLight;

  const _InlineSandboxPreview({required this.artifact, this.isLight = false});

  @override
  State<_InlineSandboxPreview> createState() => _InlineSandboxPreviewState();
}

class _InlineSandboxPreviewState extends State<_InlineSandboxPreview> {
  InAppWebViewController? _controller;
  bool _loading = true;

  void _loadSandbox() {
    final html = SandboxTemplate.wrap(
      kind: widget.artifact.kind,
      source: widget.artifact.sourceCode,
    );
    _controller?.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(
          Uri.dataFromString(
            html,
            mimeType: 'text/html',
            encoding: Encoding.getByName('utf-8'),
          ).toString(),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _InlineSandboxPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artifact.sourceCode != widget.artifact.sourceCode ||
        oldWidget.artifact.kind != widget.artifact.kind) {
      _loadSandbox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        widget.isLight ? const Color(0x1F000000) : const Color(0xFF2E2E2E);
    return Container(
      height: 340,
      decoration: BoxDecoration(
        color: widget.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF121212),
        border: Border(
          bottom: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
      child: Stack(
        children: [
          InAppWebView(
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
              // Igual que ArtifactFullscreen (C8): el artefacto viaja como
              // data URI y no puede tocar el sistema de archivos local.
              allowFileAccess: false,
              allowFileAccessFromFileURLs: false,
              allowUniversalAccessFromFileURLs: false,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              _loadSandbox();
            },
            onLoadStop: (controller, url) {
              if (mounted) setState(() => _loading = false);
            },
            onReceivedError: (controller, request, error) {
              if (mounted) setState(() => _loading = false);
            },
          ),
          if (_loading)
            const IgnorePointer(
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Badge animado en la cabecera durante la generación en streaming.
class _GeneratingBadge extends StatefulWidget {
  final bool isDark;
  const _GeneratingBadge({required this.isDark});

  @override
  State<_GeneratingBadge> createState() => _GeneratingBadgeState();
}

class _GeneratingBadgeState extends State<_GeneratingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amber =
        widget.isDark ? const Color(0xFFD4A843) : const Color(0xFF8A6A10);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_ctrl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: amber.withValues(alpha: widget.isDark ? 0.15 : 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: amber.withValues(alpha: 0.35), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: amber,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              AppI18n.of(context).t('artifacts.generating'),
              style: TextStyle(
                fontFamily: 'AnthropicSans',
                color: amber,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder animado con efecto Shimmer (estilo Claude / v0):
/// Se muestra en lugar del bloque de código mientras el modelo escribe el
/// artefacto ejecutable en streaming. Simula la silueta de un gráfico con
/// barras animadas y texto explicativo.
class _ArtifactGeneratingShimmer extends StatelessWidget {
  final bool isLight;
  final ArtifactKind kind;

  const _ArtifactGeneratingShimmer({
    required this.isLight,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppI18n.of(context).t;
    final bg = isLight ? const Color(0xFFFAFAFA) : const Color(0xFF141414);
    final borderColor =
        isLight ? const Color(0x1F000000) : const Color(0xFF2E2E2E);
    final textColor =
        isLight ? const Color(0xFF2C2A29) : const Color(0xFFE5E5EA);
    final subtextColor =
        isLight ? const Color(0xFF8E8E93) : const Color(0xFF7C7C82);

    return Container(
      height: 340,
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Esqueleto animado de silueta de gráfico con barrido Shimmer
              ExodoShimmer(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 110,
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isLight
                        ? const Color(0xFFEDE9E3)
                        : const Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isLight
                          ? const Color(0x14000000)
                          : const Color(0x1FFFFFFF),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildBar(0.35, isLight),
                      _buildBar(0.65, isLight),
                      _buildBar(0.45, isLight),
                      _buildBar(0.85, isLight),
                      _buildBar(0.55, isLight),
                      _buildBar(0.70, isLight),
                      _buildBar(0.40, isLight),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ExodoColors.amber,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    t('artifacts.building'),
                    style: TextStyle(
                      fontFamily: 'AnthropicSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                kind == ArtifactKind.svg
                    ? 'Preparando ilustración vectorial...'
                    : 'Ensamblando componente y preparando vista interactiva...',
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  fontSize: 11.5,
                  color: subtextColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBar(double heightRatio, bool isLight) {
    return Container(
      width: 14,
      height: 86 * heightRatio,
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFD4A843).withValues(alpha: 0.35)
            : const Color(0xFFD4A843).withValues(alpha: 0.4),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
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
    // Gris de acción: legible sobre cromo blanco y sobre grafito.
    final actionColor =
        isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6A63);

    Widget actionBtn({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color? color,
    }) {
      final effectiveColor = color ?? actionColor;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: effectiveColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: effectiveColor,
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
