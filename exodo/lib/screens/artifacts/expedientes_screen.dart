import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../services/expedientes_repository.dart';
import '../../services/export/exporters.dart';
import '../../data/artifacts/artifact.dart';
import 'artifact_fullscreen.dart';
import '../../theme/exodo_palette.dart';
import '../../l10n/app_i18n.dart';

/// Filter categories for the Expedientes screen.
enum _FilterCategory { all, documents, tables, interactive }

/// Maps a backend expediente category to the UI filter category.
_FilterCategory _categoryFor(String category) {
  switch (category.toLowerCase()) {
    case 'interactivo':
      return _FilterCategory.interactive;
    case 'tabla':
      return _FilterCategory.tables;
    case 'documento':
    default:
      return _FilterCategory.documents;
  }
}

/// Returns the backend category value for a filter category.
String? _categoryQuery(_FilterCategory filter) {
  switch (filter) {
    case _FilterCategory.documents:
      return 'documento';
    case _FilterCategory.tables:
      return 'tabla';
    case _FilterCategory.interactive:
      return 'interactivo';
    case _FilterCategory.all:
      return null;
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
  List<Expediente> _expedientes = [];
  final Set<String> _deletingIds = {};
  _FilterCategory _activeFilter = _FilterCategory.all;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadExpedientes();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Expediente> get _filteredExpedientes {
    var list = _expedientes;
    if (_activeFilter != _FilterCategory.all) {
      list = list.where((e) => _categoryFor(e.category) == _activeFilter).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((e) {
        final title = e.title.toLowerCase();
        final format = e.fileFormat.toLowerCase();
        final cat = e.category.toLowerCase();
        final content = (e.contentPayload ?? '').toLowerCase();
        return title.contains(q) || format.contains(q) || cat.contains(q) || content.contains(q);
      }).toList();
    }
    return list;
  }

  Future<void> _loadExpedientes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await ExpedientesRepository.instance.listExpedientes(
        category: _categoryQuery(_activeFilter),
      );
      if (!mounted) return;
      setState(() {
        _expedientes = items;
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

  Future<void> _copyLink(Expediente item) async {
    HapticFeedback.lightImpact();
    final url = item.metadata['public_url']?.toString() ?? '';
    await Clipboard.setData(ClipboardData(text: url));
  }

  Future<void> _shareLink(Expediente item) async {
    HapticFeedback.lightImpact();
    final i18n = AppI18n.of(context);
    final url = item.metadata['public_url']?.toString() ?? '';
    await ShareService.instance.shareText(
      '${i18n.t('artifacts.share_text')}: $url',
      subject: item.title,
    );
  }

  Future<void> _openFullscreen(Expediente item) async {
    HapticFeedback.lightImpact();
    String? payload = item.contentPayload;
    if (payload == null || payload.trim().isEmpty) {
      payload = item.metadata['source_code']?.toString() ??
          item.metadata['content']?.toString() ??
          item.metadata['code']?.toString();
    }
    if (payload == null || payload.trim().isEmpty) {
      final detailed = await ExpedientesRepository.instance.getExpediente(item.id);
      payload = detailed?.contentPayload ??
          detailed?.metadata['source_code']?.toString();
    }

    if (payload == null || payload.trim().isEmpty) {
      payload = '// ${item.title}\n\n// Formato: ${item.fileFormat}';
    }

    ArtifactKind kind = ArtifactKind.code;
    if (item.category == 'interactivo' &&
        (item.fileFormat == 'html' || item.fileFormat == 'react')) {
      kind = ArtifactKind.html;
    } else if (item.category == 'interactivo' && item.fileFormat == 'svg') {
      kind = ArtifactKind.svg;
    } else if (item.category == 'tabla') {
      kind = ArtifactKind.table;
    }

    final artifact = Artifact(
      id: item.id,
      messageId: item.metadata['message_id']?.toString() ?? item.id,
      conversationId: item.chatId ?? item.metadata['conversation_id']?.toString() ?? '',
      kind: kind,
      language: item.fileFormat,
      title: item.title,
      sourceCode: payload,
      meta: item.metadata,
      detectedAt: item.createdAt,
      updatedAt: item.updatedAt,
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArtifactFullscreen(artifact: artifact),
      ),
    );
  }

  Future<void> _navigateToChat(Expediente item) async {
    HapticFeedback.selectionClick();
    final chatId = item.chatId ??
        item.metadata['conversation_id']?.toString() ??
        item.metadata['chat_id']?.toString();

    final state = context.read<AppState>();
    Conversation? targetConv;

    if (chatId != null && chatId.trim().isNotEmpty) {
      targetConv =
          state.conversations.where((c) => c.id == chatId).firstOrNull;

      targetConv ??= Conversation(
        id: chatId,
        userId: state.profile?.id ?? '',
        title: item.title,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
      );
    } else {
      targetConv = state.activeConversation ?? state.conversations.firstOrNull;
    }

    if (targetConv != null) {
      await state.selectConversation(targetConv);
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // Retorna a ChatScreen
  }

  Future<void> _confirmDelete(Expediente item) async {
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

    setState(() => _deletingIds.add(item.id));

    final success = await ExpedientesRepository.instance.deleteExpediente(item.id);

    if (!mounted) return;
    setState(() => _deletingIds.remove(item.id));

    if (success) {
      HapticFeedback.lightImpact();
      setState(() {
        _expedientes.removeWhere((e) => e.id == item.id);
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
        title: _isSearching
            ? Container(
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF252525) : const Color(0xFFEAE7E0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  autofocus: true,
                  style: TextStyle(
                    fontFamily: 'AnthropicSans',
                    color: primaryTextColor,
                    fontSize: 14,
                  ),
                  cursorColor: ExodoPalette.gold,
                  decoration: InputDecoration(
                    hintText: 'Buscar en expedientes...',
                    hintStyle: TextStyle(
                      fontFamily: 'AnthropicSans',
                      color: neutralGray,
                      fontSize: 13.5,
                    ),
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: neutralGray),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            color: neutralGray,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              )
            : Text(
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
          if (_isSearching)
            IconButton(
              tooltip: 'Cerrar búsqueda',
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _searchCtrl.clear();
                setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                });
              },
            )
          else ...[
            IconButton(
              tooltip: 'Buscar expediente',
              icon: const Icon(Icons.search_rounded),
              onPressed: () {
                setState(() => _isSearching = true);
              },
            ),
            IconButton(
              tooltip: i18n.t('artifacts.refresh'),
              icon: const Icon(Icons.refresh_rounded, color: neutralGray),
              onPressed: _isLoading ? null : _loadExpedientes,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Filter chips row
          _FilterChipsRow(
            activeFilter: _activeFilter,
            isDark: isDark,
            i18n: i18n,
            onFilterChanged: (f) {
              setState(() => _activeFilter = f);
              _loadExpedientes();
            },
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
                onPressed: _loadExpedientes,
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

    final filtered = _filteredExpedientes;

    if (filtered.isEmpty && _searchQuery.trim().isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF252525) : const Color(0xFFE5E5EA),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_off_rounded,
                  size: 28,
                  color: neutralGray,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sin resultados',
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: primaryTextColor,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                i18n.t('artifacts.search_empty').replaceAll('{query}', _searchQuery),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: neutralGray,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryTextColor,
                  side: BorderSide(color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD1D1D6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
                child: Text(i18n.t('artifacts.clear_search'), style: const TextStyle(fontFamily: 'AnthropicSans', fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    if (_expedientes.isEmpty) {
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
      onRefresh: _loadExpedientes,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: filtered.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = filtered[index];
          final isDeleting = _deletingIds.contains(item.id);
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
            onNavigateToChat: () => _navigateToChat(item),
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
    final chips = <(_FilterCategory, String)>[
      (_FilterCategory.all, i18n.t('artifacts.filter_all')),
      (_FilterCategory.documents, i18n.t('artifacts.filter_docs')),
      (_FilterCategory.tables, i18n.t('artifacts.filter_tables')),
      (_FilterCategory.interactive, i18n.t('artifacts.filter_interactive')),
    ];

    final containerBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEAE7E0);
    final activePillBg = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final activeTextColor = isDark ? const Color(0xFFF5F2EB) : const Color(0xFF191919);
    final inactiveTextColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF706E6B);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: chips.map((chip) {
            final (category, label) = chip;
            final isActive = activeFilter == category;

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onFilterChanged(category);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isActive ? activePillBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'AnthropicSans',
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? activeTextColor : inactiveTextColor,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Expediente Card
// ═══════════════════════════════════════════════════════════════════════════════

class _ExpedienteCard extends StatelessWidget {
  final Expediente item;
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
  final VoidCallback onNavigateToChat;

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
    required this.onNavigateToChat,
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
    final category = _categoryFor(item.category);
    final chipBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E5EA);
    final chipBorder = isDark ? const Color(0xFF333333) : const Color(0xFFD1D1D6);
    final chipText = isDark ? const Color(0xFFC7C7CC) : const Color(0xFF48484A);

    Widget chip(String label, IconData icon, VoidCallback onTap) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
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

    final chips = <Widget>[];

    switch (category) {
      case _FilterCategory.documents:
        chips.addAll([
          chip(i18n.t('artifacts.export_pdf'), Icons.picture_as_pdf_rounded, onShare),
          const SizedBox(width: 6),
          chip(i18n.t('artifacts.export_docx'), Icons.description_outlined, onShare),
        ]);
        break;
      case _FilterCategory.tables:
        chips.addAll([
          chip(i18n.t('artifacts.export_xlsx'), Icons.table_chart_outlined, onShare),
          const SizedBox(width: 6),
          chip(i18n.t('artifacts.export_pdf'), Icons.picture_as_pdf_rounded, onShare),
        ]);
        break;
      case _FilterCategory.interactive:
        chips.addAll([
          chip(i18n.t('artifacts.share_web'), Icons.link_rounded, onCopy),
        ]);
        break;
      case _FilterCategory.all:
        chips.addAll([
          chip(i18n.t('artifacts.export_pdf'), Icons.picture_as_pdf_rounded, onShare),
        ]);
        break;
    }

    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF252525) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE2DDD5);

    return InkWell(
      onTap: onOpenFullscreen,
      borderRadius: BorderRadius.circular(14),
      child: Container(
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
              // Header: Format badge and VER EN CHAT
              Row(
                children: [
                  _FormatBadge(format: item.fileFormat, category: item.category),
                  const Spacer(),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryTextColor,
                      side: BorderSide(color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6), width: 0.8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onNavigateToChat,
                    icon: Icon(Icons.forum_outlined, size: 13, color: primaryTextColor),
                    label: Text(
                      'VER EN CHAT',
                      style: TextStyle(
                        fontFamily: 'AnthropicSans',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                        letterSpacing: 0.3,
                      ),
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

              // Updated date
              Text(
                '${i18n.t('artifacts.published')}: ${_formatDate(item.updatedAt)}',
                style: TextStyle(
                  fontFamily: 'AnthropicSans',
                  color: neutralGray,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 12),

              // Quick export action chips
              if (_buildExportActions().isNotEmpty) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _buildExportActions(),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Divider
              Divider(color: borderColor, height: 1),
              const SizedBox(height: 8),

              // Action bar (No overflow)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                      foregroundColor: primaryTextColor,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onOpenFullscreen,
                    icon: Icon(Icons.fullscreen_rounded, size: 16, color: primaryTextColor),
                    label: Text(
                      'ABRIR',
                      style: TextStyle(
                        fontFamily: 'AnthropicSans',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isDeleting)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ExodoPalette.danger,
                            ),
                          ),
                        )
                      else
                        IconButton(
                          tooltip: i18n.t('artifacts.delete_title'),
                          icon: const Icon(Icons.delete_outline_rounded, color: ExodoPalette.danger, size: 19),
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          onPressed: onDelete,
                        ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: i18n.t('act.copy'),
                        icon: Icon(Icons.copy_rounded, color: neutralGray, size: 18),
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                        onPressed: onCopy,
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                          foregroundColor: primaryTextColor,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: onShare,
                        icon: Icon(Icons.share_rounded, size: 14, color: primaryTextColor),
                        label: Text(
                          i18n.t('act.share'),
                          style: TextStyle(
                            fontFamily: 'AnthropicSans',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Format Badge
// ═══════════════════════════════════════════════════════════════════════════════

class _FormatBadge extends StatelessWidget {
  final String format;
  final String category;

  const _FormatBadge({required this.format, required this.category});

  (IconData, String, Color) _resolveMeta() {
    const brandColor = Color(0xFFD4A843);
    switch (format.toLowerCase()) {
      case 'html':
        return (Icons.html_rounded, 'HTML', brandColor);
      case 'svg':
        return (Icons.brush_rounded, 'SVG', brandColor);
      case 'pdf':
        return (Icons.picture_as_pdf_rounded, 'PDF', brandColor);
      case 'docx':
        return (Icons.description_outlined, 'DOCX', brandColor);
      case 'xlsx':
        return (Icons.table_chart_rounded, 'XLSX', brandColor);
      case 'md':
        return (Icons.article_outlined, 'MD', brandColor);
      default:
        return (Icons.code_rounded, format.toUpperCase(), brandColor);
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
