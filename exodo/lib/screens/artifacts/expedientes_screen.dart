import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/cloud_artifacts_repository.dart';
import '../../services/export/exporters.dart';
import '../../theme/exodo_palette.dart';
import '../../l10n/app_i18n.dart';



/// Filter categories for the Expedientes screen.
enum _FilterCategory { all, documents, tables, interactive }

/// Returns the filter category for a given artifact kind.
_FilterCategory _categoryFor(String kind) {
  switch (kind.toLowerCase()) {
    case 'html':
    case 'svg':
    case 'react':
    case 'mermaid':
      return _FilterCategory.interactive;
    case 'table':
    case 'json':
    case 'csv':
      return _FilterCategory.tables;
    default:
      return _FilterCategory.documents;
  }
}

/// Pantalla "Expedientes" — Records & Case Files module.
/// Displays all published artifacts with category filters and quick export actions.
class ExpedientesScreen extends StatefulWidget {
  const ExpedientesScreen({super.key});

  @override
  State<ExpedientesScreen> createState() => _ExpedientesScreenState();
}

class _ExpedientesScreenState extends State<ExpedientesScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<PublishedArtifactSummary> _artifacts = [];
  final Set<String> _deletingSlugs = {};
  _FilterCategory _activeFilter = _FilterCategory.all;

  @override
  void initState() {
    super.initState();
    _loadArtifacts();
  }

  List<PublishedArtifactSummary> get _filteredArtifacts {
    if (_activeFilter == _FilterCategory.all) return _artifacts;
    return _artifacts.where((a) => _categoryFor(a.kind) == _activeFilter).toList();
  }

  Future<void> _loadArtifacts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await CloudArtifactsRepository.instance.getMyPublishedArtifacts();
      if (!mounted) return;
      setState(() {
        _artifacts = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppI18n.of(context).t('artifacts.error_msg');
        _isLoading = false;
      });
    }
  }

  Future<void> _copyLink(PublishedArtifactSummary item) async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: item.publicUrl));
    if (!mounted) return;
    final i18n = AppI18n.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFFF5F2EB), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('${i18n.t('artifacts.copied')}: ${item.publicUrl}')),
          ],
        ),
        backgroundColor: ExodoPalette.inkRaised,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _shareLink(PublishedArtifactSummary item) async {
    HapticFeedback.lightImpact();
    final i18n = AppI18n.of(context);
    await ShareService.instance.shareText(
      '${i18n.t('artifacts.share_text')}: ${item.publicUrl}',
      subject: item.title,
    );
  }

  Future<void> _openFullscreen(PublishedArtifactSummary item) async {
    HapticFeedback.lightImpact();
    final uri = Uri.tryParse(item.publicUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirmDelete(PublishedArtifactSummary item) async {
    HapticFeedback.mediumImpact();
    final i18n = AppI18n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? ExodoPalette.inkRaised : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? ExodoPalette.inkLine : const Color(0xFFE2DDD5)),
        ),
        title: Text(
          i18n.t('artifacts.delete_title'),
          style: TextStyle(
            fontFamily: 'AnthropicSans',
            color: isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919),
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
        content: Text(
          '${item.title}\n\n${i18n.t('artifacts.delete_content')}',
          style: TextStyle(
            fontFamily: 'AnthropicSans',
            color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366),
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              i18n.t('ctx.cancel').toUpperCase(),
              style: TextStyle(
                fontFamily: 'AnthropicSans',
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ExodoPalette.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              i18n.t('ctx.delete').toUpperCase(),
              style: const TextStyle(
                fontFamily: 'AnthropicSans',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    setState(() => _deletingSlugs.add(item.slug));

    final success = await CloudArtifactsRepository.instance.deletePublishedArtifact(item.slug);

    if (!mounted) return;
    setState(() => _deletingSlugs.remove(item.slug));

    if (success) {
      HapticFeedback.lightImpact();
      setState(() {
        _artifacts.removeWhere((a) => a.slug == item.slug);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(i18n.t('artifacts.deleted')),
          backgroundColor: ExodoPalette.inkRaised,
        ),
      );
    } else {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(i18n.t('artifacts.delete_failed')),
          backgroundColor: ExodoPalette.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final i18n = AppI18n.of(context);

    const chalk = Color(0xFFF5F2EB);
    const neutralGray = Color(0xFF8E8E93);
    final primaryTextColor = isDark ? chalk : const Color(0xFF191919);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: scaffoldBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: primaryTextColor),
        title: Text(
          i18n.t('artifacts.title'),
          style: TextStyle(
            fontFamily: 'AnthropicSans',
            color: primaryTextColor,
            fontWeight: FontWeight.w600,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: i18n.t('artifacts.refresh'),
            icon: const Icon(Icons.refresh_rounded, color: neutralGray),
            onPressed: _isLoading ? null : _loadArtifacts,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips row
          _FilterChipsRow(
            activeFilter: _activeFilter,
            isDark: isDark,
            i18n: i18n,
            onFilterChanged: (f) => setState(() => _activeFilter = f),
          ),
          // Content body
          Expanded(
            child: _buildBody(isDark, chalk, neutralGray, primaryTextColor, i18n),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    bool isDark,
    Color chalk,
    Color neutralGray,
    Color primaryTextColor,
    AppI18n i18n,
  ) {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: neutralGray,
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: ExodoPalette.danger),
              const SizedBox(height: 16),
              Text(
                i18n.t('artifacts.error_title'),
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: primaryTextColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: neutralGray,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                  foregroundColor: primaryTextColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                ),
                onPressed: _loadArtifacts,
                icon: Icon(Icons.refresh_rounded, size: 16, color: primaryTextColor),
                label: Text(
                  i18n.t('artifacts.retry'),
                  style: const TextStyle(
                    fontFamily: 'AnthropicSans',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredArtifacts;

    if (_artifacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF252525) : const Color(0xFFE5E5EA),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.folder_copy_outlined,
                  size: 32,
                  color: neutralGray,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                i18n.t('artifacts.empty_title'),
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: primaryTextColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                i18n.t('artifacts.empty_desc'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: neutralGray,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryTextColor,
                  side: BorderSide(color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD1D1D6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.chat_bubble_outline_rounded, size: 16, color: neutralGray),
                label: Text(
                  i18n.t('artifacts.back_chat'),
                  style: const TextStyle(
                    fontFamily: 'AnthropicSans',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (filtered.isEmpty) {
      // Active filter yields no results
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_list_off_rounded, size: 40, color: neutralGray),
              const SizedBox(height: 14),
              Text(
                i18n.t('artifacts.empty_title'),
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: primaryTextColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: neutralGray,
      backgroundColor: isDark ? ExodoPalette.inkRaised : Colors.white,
      onRefresh: _loadArtifacts,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: filtered.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = filtered[index];
          final isDeleting = _deletingSlugs.contains(item.slug);
          return _ExpedienteCard(
            item: item,
            isDeleting: isDeleting,
            isDark: isDark,
            chalk: const Color(0xFFF5F2EB),
            neutralGray: const Color(0xFF8E8E93),
            primaryTextColor: isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919),
            i18n: i18n,
            onCopy: () => _copyLink(item),
            onShare: () => _shareLink(item),
            onDelete: () => _confirmDelete(item),
            onOpenFullscreen: () => _openFullscreen(item),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Filter Chips Row
// ═══════════════════════════════════════════════════════════════════════════════

class _FilterChipsRow extends StatelessWidget {
  final _FilterCategory activeFilter;
  final bool isDark;
  final AppI18n i18n;
  final ValueChanged<_FilterCategory> onFilterChanged;

  const _FilterChipsRow({
    required this.activeFilter,
    required this.isDark,
    required this.i18n,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <(_FilterCategory, String, String)>[
      (_FilterCategory.all, i18n.t('artifacts.filter_all'), '📋'),
      (_FilterCategory.documents, i18n.t('artifacts.filter_docs'), '📄'),
      (_FilterCategory.tables, i18n.t('artifacts.filter_tables'), '📊'),
      (_FilterCategory.interactive, i18n.t('artifacts.filter_interactive'), '🌐'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: chips.map((chip) {
          final (category, label, emoji) = chip;
          final isActive = activeFilter == category;
          final activeBg = isDark ? const Color(0xFF2A2520) : const Color(0xFFE8E4DB);
          final inactiveBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0EDE6);
          final activeTextColor = isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919);
          final inactiveTextColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366);
          final borderColor = isActive
              ? (isDark ? const Color(0xFFD4A843).withValues(alpha: 0.5) : const Color(0xFFD4A843).withValues(alpha: 0.4))
              : (isDark ? const Color(0xFF2A2A2C) : const Color(0xFFD1D1D6));

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onFilterChanged(category);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isActive ? activeBg : inactiveBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: isActive ? 1.2 : 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'AnthropicSans',
                        fontSize: 12.5,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? activeTextColor : inactiveTextColor,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Expediente Card
// ═══════════════════════════════════════════════════════════════════════════════

class _ExpedienteCard extends StatelessWidget {
  final PublishedArtifactSummary item;
  final bool isDeleting;
  final bool isDark;
  final Color chalk;
  final Color neutralGray;
  final Color primaryTextColor;
  final AppI18n i18n;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onOpenFullscreen;

  const _ExpedienteCard({
    required this.item,
    required this.isDeleting,
    required this.isDark,
    required this.chalk,
    required this.neutralGray,
    required this.primaryTextColor,
    required this.i18n,
    required this.onCopy,
    required this.onShare,
    required this.onDelete,
    required this.onOpenFullscreen,
  });

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y · $h:$min';
  }

  /// Build quick-export action chips based on artifact kind category.
  List<Widget> _buildExportActions() {
    final category = _categoryFor(item.kind);
    final chipBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E5EA);
    final chipBorder = isDark ? const Color(0xFF333333) : const Color(0xFFD1D1D6);
    final chipText = isDark ? const Color(0xFFC7C7CC) : const Color(0xFF48484A);

    Widget chip(String label, IconData icon, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: chipBorder, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: chipText),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: chipText,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      );
    }

    switch (category) {
      case _FilterCategory.documents:
        return [
          chip(i18n.t('artifacts.export_pdf'), Icons.picture_as_pdf_rounded, onShare),
          const SizedBox(width: 6),
          chip(i18n.t('artifacts.export_docx'), Icons.description_outlined, onShare),
        ];
      case _FilterCategory.tables:
        return [
          chip(i18n.t('artifacts.export_xlsx'), Icons.table_chart_outlined, onShare),
          const SizedBox(width: 6),
          chip(i18n.t('artifacts.export_pdf'), Icons.picture_as_pdf_rounded, onShare),
        ];
      case _FilterCategory.interactive:
        return [
          chip(i18n.t('artifacts.open_fullscreen'), Icons.open_in_new_rounded, onOpenFullscreen),
          const SizedBox(width: 6),
          chip(i18n.t('artifacts.share_web'), Icons.link_rounded, onCopy),
        ];
      case _FilterCategory.all:
        // Default actions
        return [
          chip(i18n.t('artifacts.export_pdf'), Icons.picture_as_pdf_rounded, onShare),
          const SizedBox(width: 6),
          chip(i18n.t('artifacts.share_web'), Icons.link_rounded, onCopy),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF252525) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2520) : const Color(0xFFE2DDD5);
    final viewsLabel = item.viewsCount == 1 ? i18n.t('artifacts.view') : i18n.t('artifacts.views');

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Kind badge + views counter
            Row(
              children: [
                _KindBadge(kind: item.kind, language: item.language),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF191919) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_outlined, size: 13, color: neutralGray),
                      const SizedBox(width: 5),
                      Text(
                        '${item.viewsCount} $viewsLabel',
                        style: TextStyle(
                          fontFamily: 'AnthropicSans',
                          color: neutralGray,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              item.title,
              style: TextStyle(
                fontFamily: 'AnthropicSans',
                color: primaryTextColor,
                fontWeight: FontWeight.w600,
                fontSize: 15.5,
                letterSpacing: -0.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),

            // Published date
            Text(
              '${i18n.t('artifacts.published')}: ${_formatDate(item.createdAt)}',
              style: TextStyle(
                fontFamily: 'AnthropicSans',
                color: neutralGray,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 12),

            // Quick export action chips
            Row(
              children: _buildExportActions(),
            ),
            const SizedBox(height: 10),

            // Divider
            Divider(color: borderColor, height: 1),
            const SizedBox(height: 8),

            // Action bar
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isDeleting)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ExodoPalette.danger,
                      ),
                    ),
                  )
                else
                  IconButton(
                    tooltip: i18n.t('artifacts.delete_title'),
                    icon: const Icon(Icons.delete_outline_rounded, color: ExodoPalette.danger, size: 20),
                    onPressed: onDelete,
                  ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: i18n.t('act.copy'),
                  icon: Icon(Icons.copy_rounded, color: neutralGray, size: 19),
                  onPressed: onCopy,
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                    foregroundColor: primaryTextColor,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: onShare,
                  icon: Icon(Icons.share_rounded, size: 15, color: primaryTextColor),
                  label: Text(
                    i18n.t('act.share').toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'AnthropicSans',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Kind Badge
// ═══════════════════════════════════════════════════════════════════════════════

class _KindBadge extends StatelessWidget {
  final String kind;
  final String? language;

  const _KindBadge({required this.kind, this.language});

  (IconData, String, Color) _resolveMeta() {
    switch (kind.toLowerCase()) {
      case 'html':
        return (Icons.html_rounded, 'HTML', const Color(0xFFE44D26));
      case 'svg':
        return (Icons.brush_rounded, 'SVG', const Color(0xFFFFB13B));
      case 'mermaid':
        return (Icons.account_tree_rounded, 'MERMAID', const Color(0xFF00C853));
      case 'react':
        return (Icons.code_rounded, 'REACT', const Color(0xFF61DAFB));
      case 'table':
        return (Icons.table_chart_rounded, 'TABLA', const Color(0xFF4CAF50));
      case 'json':
        return (Icons.data_object_rounded, 'JSON', const Color(0xFFFF9800));
      default:
        final label = (language != null && language!.isNotEmpty) ? language!.toUpperCase() : 'CÓDIGO';
        return (Icons.code_rounded, label, const Color(0xFF8E8E93));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _resolveMeta();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'AnthropicSans',
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
