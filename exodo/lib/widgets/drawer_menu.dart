import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/supabase_service.dart';
import '../services/widget_service.dart';
import '../theme/exodo_theme.dart';
import '../l10n/app_i18n.dart';
import '../l10n/app_translations.dart';
import '../screens/profile_screen.dart';

/// Item de menú reutilizable con padding responsive.
class _DrawerItem extends StatelessWidget {
  final Widget icon;
  final Widget title;
  final VoidCallback onTap;
  final double horizontalPad;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.horizontalPad,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: horizontalPad),
      leading: icon,
      title: title,
      onTap: onTap,
    );
  }
}

class DrawerMenu extends StatefulWidget {
  const DrawerMenu({super.key});

  @override
  State<DrawerMenu> createState() => _DrawerMenuState();
}

class _DrawerMenuState extends State<DrawerMenu> {
  Set<String> _matchingIds = {};
  String _searchQuery = '';
  bool _isSearching = false;
  bool _showVersion = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLight = !state.isDarkMode;
    final bg = isLight ? ExodoColors.textPrimary : ExodoColors.background;
    final textCol = isLight ? const Color(0xFF171615) : ExodoColors.textPrimary;
    final subTextCol = isLight ? Colors.black54 : ExodoColors.textSecondary;

    final filtered = state.conversations.where((c) {
      if (_searchQuery.isEmpty) return true;
      return c.title.toLowerCase().contains(_searchQuery.toLowerCase()) || _matchingIds.contains(c.id);
    }).toList();

    // Fase 2: leer/escribir fijados únicamente desde DB (c.isStarred).
    final starredConvs = filtered.where((c) => c.isStarred).toList();
    final recentConvs = filtered.where((c) => !c.isStarred).toList();

    // ============================================================
    // RESPONSIVE: el drawer se adapta al ancho de pantalla sin
    // tocar los bordes. Tamaños calculados proporcionalmente a
    // un ancho base de 360 dp (LG V60 ~390 dp).
    // ============================================================
    final mq = MediaQuery.of(context);
    final scale = (mq.size.width / 360.0).clamp(0.85, 1.20);
    final hPad = (20.0 * scale).clamp(16.0, 24.0);

    double s(double v) => v * scale;

    final logoH = s(44).clamp(36.0, 52.0);
    final exodoTextH = s(30).clamp(24.0, 36.0);
    final avatarR = s(22).clamp(18.0, 26.0);
    final bybehaviorH = s(28).clamp(22.0, 34.0);

    return Drawer(
      backgroundColor: bg,
      child: SafeArea(
        child: Stack(
          children: [
            // Capa 1: Column con header + historial (este último scrollea)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1-3. Header fijo con fondo sólido para evitar cualquier transparencia o solapamiento con el historial
                Material(
                  color: bg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Header fijo: Logo_behavior + exodo_text (izquierda) + botón cerrar (derecha)
                      Padding(
                        padding: EdgeInsets.fromLTRB(hPad, s(28), s(12), _showVersion ? 8 : s(18)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      setState(() => _showVersion = !_showVersion);
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Image.asset(
                                          'assets/images/Logo_behavior.png',
                                          height: logoH,
                                          color: ExodoColors.amber,
                                        ),
                                        SizedBox(width: s(10)),
                                        Flexible(
                                          child: Image.asset(
                                            'assets/images/exodo_text.png',
                                            height: exodoTextH,
                                            color: textCol,
                                            fit: BoxFit.scaleDown,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close_rounded, color: subTextCol, size: s(20)),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                            if (_showVersion) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isLight ? const Color(0xFFF5F2EB) : const Color(0xFF131313),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: ExodoColors.amber.withValues(alpha: 0.3), width: 0.8),
                                ),
                                child: Text(
                                  'AVI 1.1.86-release.01',
                                  style: TextStyle(fontFamily: 'AnthropicSans', 
                                    fontSize: 10.5,
                                    color: ExodoColors.amber,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // 2. Opciones de menú.
                      IntrinsicHeight(
                        child: Wrap(
                          spacing: 0,
                          runSpacing: 0,
                          children: [
                            _DrawerItem(
                              horizontalPad: hPad,
                              icon: Icon(Icons.chat_bubble_outline_rounded, size: s(20), color: textCol),
                              title: Text(AppI18n.of(context).t('drawer.new_chat'), style: TextStyle(fontFamily: 'AnthropicSans', fontSize: s(14), color: textCol, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                              onTap: () {
                                state.startNewChat();
                                Navigator.pop(context);
                              },
                            ),
                            _DrawerItem(
                              horizontalPad: hPad,
                              icon: Icon(state.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: s(20), color: textCol),
                              title: Text(state.isDarkMode ? AppI18n.of(context).t('drawer.light_mode') : AppI18n.of(context).t('drawer.dark_mode'), style: TextStyle(fontFamily: 'AnthropicSans', fontSize: s(14), color: textCol, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                              onTap: () => state.toggleTheme(),
                            ),
                            _DrawerItem(
                              horizontalPad: hPad,
                              icon: Image.asset(
                                'assets/images/incognito-svgrepo-com.png',
                                width: s(20),
                                height: s(20),
                                color: state.isIncognito ? ExodoColors.amber : textCol,
                              ),
                              title: Text(AppI18n.of(context).t('drawer.incognito'), style: TextStyle(fontFamily: 'AnthropicSans', fontSize: s(14), color: state.isIncognito ? ExodoColors.amber : textCol, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                              onTap: () {
                                HapticFeedback.vibrate();
                                state.toggleIncognito();
                              },
                            ),
                          ],
                        ),
                      ),

                      // 3. Buscar conversación
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPad - s(8), vertical: 2),
                        child: _isSearching
                            ? Container(
                                height: s(38).clamp(34.0, 44.0),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                margin: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: isLight ? Colors.white : ExodoColors.composerBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.search, size: s(18), color: subTextCol),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _searchCtrl,
                                        autofocus: true,
                                        cursorColor: textCol,
                                        style: TextStyle(fontSize: s(13), color: textCol),
                                        decoration: InputDecoration(
                                          hintText: AppI18n.of(context).t('drawer.search_chats'),
                                          hintStyle: TextStyle(fontSize: s(13), color: subTextCol),
                                          filled: false,
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          disabledBorder: InputBorder.none,
                                          contentPadding: EdgeInsets.zero,
                                          isDense: true,
                                        ),
                                        onChanged: (v) {
                                          setState(() => _searchQuery = v);
                                          if (v.trim().length >= 2) {
                                            SupabaseService.searchConversationIdsByMessage(v.trim()).then((ids) {
                                              if (mounted && _searchQuery == v) {
                                                setState(() => _matchingIds = ids.toSet());
                                              }
                                            });
                                          } else {
                                            setState(() => _matchingIds.clear());
                                          }
                                        },
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        _searchCtrl.clear();
                                        setState(() {
                                          _searchQuery = '';
                                          _matchingIds.clear();
                                          _isSearching = false;
                                        });
                                      },
                                      child: Icon(Icons.close, size: s(16), color: subTextCol),
                                    ),
                                  ],
                                ),
                              )
                            : _DrawerItem(
                                horizontalPad: hPad - s(8),
                                icon: Icon(Icons.search_rounded, size: s(20), color: textCol),
                                title: Text(AppI18n.of(context).t('drawer.search_chats'), style: TextStyle(fontFamily: 'AnthropicSans', fontSize: s(14), color: textCol, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                                onTap: () => setState(() => _isSearching = true),
                              ),
                      ),

                      const SizedBox(height: 6),
                      Divider(color: isLight ? const Color(0xFFE2DDD2) : const Color(0xFF212121), height: 1),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                // 4. Historial (Expanded real, con ClipRect para truncar cualquier scroll o stretch de Android)
                Expanded(
                  child: ClipRect(
                    child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Ícono suave amber con glow sutil.
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: ExodoColors.amber.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: ExodoColors.amber.withValues(alpha: 0.25),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    state.conversations.isEmpty
                                        ? Icons.chat_bubble_outline_rounded
                                        : Icons.search_off_rounded,
                                    size: 26,
                                    color: ExodoColors.amber.withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  state.conversations.isEmpty
                                      ? AppI18n.of(context).t('drawer.no_history')
                                      : AppI18n.of(context).t('drawer.no_found'),
                                  style: TextStyle(fontFamily: 'AnthropicSans', 
                                    fontSize: s(13),
                                    color: subTextCol,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.1,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  state.conversations.isEmpty
                                      ? AppI18n.of(context).t('drawer.start_conv')
                                      : AppI18n.of(context).t('drawer.try_search'),
                                  style: GoogleFonts.inter(
                                    fontSize: s(12),
                                    color: subTextCol.withValues(alpha: 0.7),
                                    height: 1.4,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : CustomScrollView(
                          slivers: [
                            if (starredConvs.isNotEmpty) ...[
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 4),
                                sliver: SliverToBoxAdapter(
                                  child: Text(AppI18n.of(context).t('drawer.starred'), style: TextStyle(fontFamily: 'AnthropicSans', fontSize: s(11.5), fontWeight: FontWeight.bold, color: subTextCol, letterSpacing: -0.1)),
                                ),
                              ),
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _buildConvItem(starredConvs[index], state, isLight, true, hPad, s),
                                  childCount: starredConvs.length,
                                ),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 10)),
                            ],

                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 4),
                              sliver: SliverToBoxAdapter(
                                child: Text(AppI18n.of(context).t('drawer.recents'), style: TextStyle(fontFamily: 'AnthropicSans', fontSize: s(11.5), fontWeight: FontWeight.bold, color: subTextCol, letterSpacing: -0.1)),
                              ),
                            ),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => _buildConvItem(recentConvs[index], state, isLight, false, hPad, s),
                                childCount: recentConvs.length,
                              ),
                            ),
                            // Padding inferior para que el último item no quede tapado por el footer
                            const SliverToBoxAdapter(child: SizedBox(height: 130)),
                          ],
                        ),
                  ),
                ),
              ],
            ),

            // Capa 2: Footer anclado al fondo (Stack), siempre visible, NO se mueve con el historial
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: bg, // mismo fondo del drawer
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Divider(color: isLight ? const Color(0xFFE2DDD2) : const Color(0xFF212121), height: 1),
                    Padding(
                      padding: EdgeInsets.fromLTRB(hPad, s(12), hPad, s(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _ClaudeAccountModal.show(context, state),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: avatarR,
                                  backgroundColor: ExodoColors.amber,
                                  backgroundImage: (state.userAvatarUrl != null)
                                      ? NetworkImage(state.userAvatarUrl!)
                                      : null,
                                  child: (state.userAvatarUrl != null)
                                      ? null
                                      : Text(
                                          (state.profile?.fullName?.trim().isNotEmpty == true)
                                              ? state.profile!.fullName!.trim().substring(0, 1).toUpperCase()
                                              : 'U',
                                          style: TextStyle(fontFamily: 'Syne', fontSize: s(19), fontWeight: FontWeight.bold, color: Colors.black),
                                        ),
                                ),
                                SizedBox(width: s(12)),
                                Flexible(
                                  child: Text(
                                    state.profile?.fullName ?? AppI18n.of(context).t('drawer.user_default'),
                                    style: TextStyle(fontFamily: 'AnthropicSans', fontSize: s(14), fontWeight: FontWeight.w600, color: textCol, letterSpacing: -0.2),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: s(10)),
                          Image.asset(
                            'assets/images/bybehavior_text.png',
                            height: bybehaviorH,
                            color: isLight ? const Color(0xFF66605A) : ExodoColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
// [v1.1] Sheet para anclar un Gadget (App Widget) a la pantalla
// de inicio via WidgetService. Estilo Éxodo (dark, amber, mono).
// ============================================================
// ignore: unused_element
void _showAddWidgetSheet(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: ExodoColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.widgets_outlined, color: ExodoColors.amber, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppI18n.of(sheetCtx).t('drawer.add_widget'),
                        style: TextStyle(fontFamily: 'Syne', 
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: ExodoColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Elige el estilo de widget flotante inteligente que mejor combine con tu fondo de pantalla:",
                  style: GoogleFonts.inter(fontSize: 13, color: ExodoColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 18),
                InkWell(
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    HapticFeedback.selectionClick();
                    await WidgetService.instance.requestPinWidget(type: 'grok');
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: ExodoColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: ExodoColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E0C0A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: ExodoColors.amber.withValues(alpha: 0.4)),
                          ),
                          child: const Icon(Icons.dark_mode_outlined, color: ExodoColors.amber, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Widget Éxodo Oscuro",
                                style: GoogleFonts.inter(fontSize: 15, color: ExodoColors.textPrimary, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Estilo Negro Cálido minimalista",
                                style: GoogleFonts.inter(fontSize: 12, color: ExodoColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: ExodoColors.textSecondary, size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    HapticFeedback.selectionClick();
                    await WidgetService.instance.requestPinWidget(type: 'grok_light');
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F2EB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE0DDD6)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEBE7DE),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: ExodoColors.amber),
                          ),
                          child: const Icon(Icons.light_mode_outlined, color: ExodoColors.amber, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Widget Éxodo Claro",
                                style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF0E0C0A), fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Estilo Yeso / Hueso luminoso",
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B655B)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Color(0xFF0E0C0A), size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

// ============================================================
  // ============================================================

  Widget _buildConvItem(Conversation conv, AppState state, bool isLight, bool isStarred, double hPad, double Function(double) s) {
    final active = state.activeConversation?.id == conv.id;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: (hPad - s(10)).clamp(0.0, 10.0), vertical: 1),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: s(12)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: active ? (isLight ? const Color(0xFFEBE7DE) : const Color(0xFF212121)) : Colors.transparent,
        onTap: () {
          state.selectConversation(conv);
          Navigator.pop(context);
        },
        onLongPress: () {
          HapticFeedback.vibrate();
          _showChatContextMenu(context, conv, state, isStarred);
        },
        title: Text(
          (conv.title == 'New chat' || conv.title == 'Nuevo chat' || conv.title == 'Nueva conversación' || conv.title == 'Nova conversa' || conv.title == 'Nouvelle conversation' || conv.title == 'Nuova chat' || conv.title == 'Neuer Chat' || conv.title == 'New conversation' || conv.title == 'Sin título') ? AppI18n.of(context).t('drawer.new_chat') : conv.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'AnthropicSans', 
            fontSize: s(13),
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? (isLight ? Colors.black : ExodoColors.textPrimary) : (isLight ? const Color(0xFF171615) : ExodoColors.textPrimary),
            letterSpacing: -0.1,
          ),
        ),
        trailing: isStarred
            ? Icon(Icons.push_pin_rounded, size: s(14), color: isLight ? Colors.black54 : Colors.white70)
            : null,
      ),
    );
  }

  void _showChatContextMenu(BuildContext context, Conversation conv, AppState state, bool isStarred) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    showModalBottomSheet(
      context: context,
      backgroundColor: isLight ? ExodoColors.lightSheetBg : ExodoColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: isLight ? Colors.black12 : Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: isLight ? Colors.black87 : Colors.white),
              title: Text(AppI18n.of(context).t('ctx.rename'), style: GoogleFonts.inter(fontSize: 15, color: isLight ? Colors.black : Colors.white, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, conv, state);
              },
            ),
            ListTile(
              leading: Icon(isStarred ? Icons.push_pin : Icons.push_pin_outlined, color: isLight ? Colors.black87 : Colors.white),
              title: Text(isStarred ? AppI18n.of(context).t('ctx.unpin') : AppI18n.of(context).t('ctx.pin'), style: GoogleFonts.inter(fontSize: 15, color: isLight ? Colors.black : Colors.white, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                // Fase 2: la DB se actualiza vía AppState.toggleStarConversation.
                // El setState() dispara el rebuild del drawer para reflejar el cambio.
                state.toggleStarConversation(conv.id);
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(AppI18n.of(context).t('ctx.delete'), style: GoogleFonts.inter(fontSize: 15, color: Colors.redAccent, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteConfirmationDialog(context, conv, state);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, Conversation conv, AppState state) {
    final ctrl = TextEditingController(text: conv.title);
    final isLight = Theme.of(context).brightness == Brightness.light;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isLight ? ExodoColors.lightSheetBg : ExodoColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppI18n.of(context).t('dialog.rename_chat'), style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: isLight ? Colors.black : Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: isLight ? Colors.black : Colors.white),
          decoration: InputDecoration(
            hintText: AppI18n.of(context).t('dialog.conv_title'),
            hintStyle: TextStyle(color: isLight ? Colors.black38 : Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isLight ? Colors.black26 : Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: isLight ? Colors.black : Colors.white)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppI18n.of(context).t('ctx.cancel'), style: TextStyle(color: isLight ? Colors.black54 : Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final newTitle = ctrl.text.trim();
              if (newTitle.isNotEmpty) {
                state.renameConversation(conv.id, newTitle);
              }
              Navigator.pop(ctx);
            },
            child: Text(AppI18n.of(context).t('action.save'), style: TextStyle(color: isLight ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, Conversation conv, AppState state) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isLight ? ExodoColors.lightSheetBg : ExodoColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Text(
              AppI18n.of(context).t('dialog.delete_chat'),
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: isLight ? Colors.black : Colors.white),
            ),
          ],
        ),
        content: Text(
          '${AppI18n.of(context).t('dialog.delete_chat_body')} "${conv.title}"?',
          style: GoogleFonts.inter(fontSize: 14, color: isLight ? Colors.black87 : Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppI18n.of(context).t('ctx.cancel'), style: TextStyle(color: isLight ? Colors.black54 : Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await state.deleteConversation(conv.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(AppI18n.of(context).t('ctx.delete'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// Modal estilo Claude Settings (fotos adjuntas)
/// Tile reutilizable para el selector de idioma.
class _LangTile extends StatelessWidget {
  final String flag;
  final String title;
  final String subtitle;
  final bool selected;
  final Color textCol;
  final Color subTextCol;
  final VoidCallback onTap;

  const _LangTile({
    required this.flag,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.textCol,
    required this.subTextCol,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Text(flag, style: const TextStyle(fontSize: 22)),
      title: Text(
        title,
        style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: textCol),
      ),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: subTextCol)),
      trailing: selected
          ? Icon(Icons.check_circle, size: 20, color: ExodoColors.amber)
          : const SizedBox(width: 20),
      onTap: onTap,
    );
  }
}

class _ClaudeAccountModal {
  static void show(BuildContext context, AppState state) {
    final isLight = !state.isDarkMode;
    final bg = isLight ? Colors.white : ExodoColors.background;
    final textCol = isLight ? const Color(0xFF191919) : ExodoColors.textPrimary;
    final subTextCol = isLight ? const Color(0xFF191919) : ExodoColors.textPrimary;
    final cardBg = isLight ? ExodoColors.textPrimary : ExodoColors.composerBg;
    final borderColor = isLight ? const Color(0xFFE8E0D8) : Colors.transparent;
    final handleColor = isLight ? Colors.black26 : ExodoColors.textPrimary.withValues(alpha: 0.3);
    final dividerColor = isLight ? const Color(0xFFE2DDD2) : Colors.transparent;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        // [Punto 35 aviso] 254 PIXELS overflow: el Column con muchos tiles
        // excedía el alto del bottom sheet. SingleChildScrollView permite
        // scroll cuando el contenido es más grande que la pantalla.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con tirador y título Settings
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: handleColor, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Center(
                child: Text(AppI18n.of(context).t('settings.title'), style: TextStyle(fontFamily: 'Syne', fontSize: 18, fontWeight: FontWeight.bold, color: textCol)),
              ),
              const SizedBox(height: 20),

              // Tarjeta superior: Correo + Etiqueta Free/Pro (sin "Want more Claude")
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        state.userEmail.isNotEmpty ? state.userEmail : AppI18n.of(context).t('settings.no_email'),
                        style: TextStyle(fontFamily: 'AnthropicSans', fontSize: 14, fontWeight: FontWeight.w600, color: state.userEmail.isNotEmpty ? textCol : subTextCol, letterSpacing: -0.2),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: isLight ? const Color(0xFF171615) : ExodoColors.textPrimary, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        state.profile?.plan == 'hazak' ? 'Pro' : 'Free',
                        style: TextStyle(fontFamily: 'AnthropicSans', fontSize: 12, fontWeight: FontWeight.bold, color: isLight ? Colors.white : ExodoColors.background, letterSpacing: -0.2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Opciones de lista con diseño limpio
              // [v1.0] Profile y Billing NO están disponibles para usuarios guest.
              // Solo aparecen tras login (Google/Email/Incognito registrado).
              if (!state.isGuestUser) ...[
                _buildSettingTile(
                  icon: Icons.person_outline_rounded,
                  title: AppI18n.of(context).t('settings.profile'),
                  isLight: isLight,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                  },
                ),
                const SizedBox(height: 8),
              ],
              _buildSettingTile(
                icon: Icons.language_rounded,
                title: AppI18n.of(context).t('drawer.language'),
                subtitle: _currentLocaleFlag(context),
                isLight: isLight,
                onTap: () {
                  Navigator.pop(ctx);
                  _showLanguageSheet(context);
                },
              ),
              const SizedBox(height: 8),
              if (!state.isGuestUser) ...[
                _buildSettingTile(
                  icon: Icons.monetization_on_outlined,
                  title: AppI18n.of(context).t('settings.billing'),
                  isLight: isLight,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showBillingModal(context, state);
                  },
                ),
                const SizedBox(height: 8),
              ],

              _buildSettingTile(
                assetIcon: 'assets/images/laptop-alt-2-svgrepo-com.png',
                title: AppI18n.of(context).t('drawer.web'),
                isLight: isLight,
                onTap: () {},
              ),
              const SizedBox(height: 8),
              _buildSettingTile(
                icon: Icons.privacy_tip_outlined,
                title: AppI18n.of(context).t('settings.terms'),
                isLight: isLight,
                onTap: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: bg,
                      title: Text(AppI18n.of(context).t('settings.terms'), style: TextStyle(fontFamily: 'Syne', color: textCol)),
                      content: Text(AppI18n.of(context).t('settings.legal_body'), style: GoogleFonts.inter(color: subTextCol)),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(AppI18n.of(context).t('action.close'), style: const TextStyle(color: ExodoColors.amber)))],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Divider(color: dividerColor),
              const SizedBox(height: 8),

              // Botón de Log out abajo en tono rojizo
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.logout_rounded, color: Color(0xFFE57373), size: 22),
                title: Text(AppI18n.of(context).t('settings.logout'), style: TextStyle(fontFamily: 'AnthropicSans', fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFFE57373), letterSpacing: -0.2)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Future.delayed(const Duration(milliseconds: 300));
                  await SupabaseService.signOut();
                },
              ),
              const SizedBox(height: 24),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/Logo_behavior.png',
                      height: 16,
                      color: isLight ? Colors.black54 : ExodoColors.textPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'AVI 1.1.86-release.01',
                      style: TextStyle(fontFamily: 'AnthropicSans', 
                        fontSize: 12,
                        color: isLight ? Colors.black54 : ExodoColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildSettingTile({
    IconData? icon,
    String? assetIcon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    required bool isLight,
  }) {
    final tileBg = isLight ? ExodoColors.textPrimary : ExodoColors.composerBg;
    final textCol = isLight ? const Color(0xFF191919) : ExodoColors.textPrimary;
    final subCol = isLight ? const Color(0xFF191919) : ExodoColors.textPrimary;
    final iconCol = isLight ? const Color(0xFF191919) : ExodoColors.textPrimary;
    final chevronCol = isLight ? const Color(0xFF191919) : ExodoColors.textPrimary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            if (assetIcon != null)
              Image.asset(assetIcon, width: 22, height: 22, color: iconCol)
            else if (icon != null)
              Icon(icon, color: iconCol, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TextStyle(fontFamily: 'AnthropicSans', fontSize: 15, color: textCol, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontFamily: 'AnthropicSans', fontSize: 12, color: subCol, letterSpacing: -0.2)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: chevronCol, size: 20),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Idioma: helper y sheet movidos aquí (estaban en _DrawerMenuState).
  // ============================================================

  /// Devuelve "🇪🇸 Español" o el locale seleccionado en la app.
  /// Antes leía el locale del sistema operativo (PlatformDispatcher); ahora
  /// usa AppI18n.of(context).localeCode que respeta el override del usuario
  /// y cae al sistema si no hay override (lógica encapsulada en app_i18n.dart).
  static String _currentLocaleFlag(BuildContext context) {
    final code = AppI18n.of(context).localeCode;
    final match = kAppLocales.firstWhere((l) => l.code == code, orElse: () => kAppLocales.first);
    return '${match.nativeName} ${match.flag}';
  }

  /// Sheet selector de idioma. 6 disponibles + opción "Predeterminado
  /// del sistema". El sheet se cierra solo al elegir; la app entera se
  /// rerenderiza por el InheritedWidget del AppI18nProvider.
  static void _showLanguageSheet(BuildContext context) {
    final i18n = AppI18n.of(context);
    final currentCode = context.currentLocaleCode;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? ExodoColors.lightSheetBg : ExodoColors.background;
    final textCol = isLight ? const Color(0xFF171615) : ExodoColors.textPrimary;
    final subTextCol = isLight ? Colors.black54 : ExodoColors.textPrimary;

    HapticFeedback.selectionClick();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * 0.75),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: subTextCol.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    i18n.t('lang.sheet_title'),
                    style: TextStyle(fontFamily: 'Syne', fontSize: 18, fontWeight: FontWeight.bold, color: textCol),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    i18n.t('lang.sheet_subtitle'),
                    style: GoogleFonts.inter(fontSize: 12.5, color: subTextCol),
                  ),
                ),
              ),
              // Opción "Predeterminado del sistema"
              _LangTile(
                flag: '🌐',
                title: i18n.t('lang.system'),
                subtitle: 'Auto-detect',
                selected: currentCode == null,
                textCol: textCol,
                subTextCol: subTextCol,
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await sheetCtx.setLocale(null);
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                },
              ),
              Divider(color: subTextCol.withValues(alpha: 0.2), height: 1, indent: 20, endIndent: 20),
              // Lista de idiomas disponibles - envuelta en Flexible + ListView.builder
              // para que scrollee sin RenderFlex overflow cuando hay muchos
              // idiomas o el modal se abre en pantallas pequenas.
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: kAppLocales.length,
                  itemBuilder: (_, i) {
                    final loc = kAppLocales[i];
                    return _LangTile(
                      flag: loc.flag,
                      title: loc.nativeName,
                      subtitle: loc.code.toUpperCase(),
                      selected: currentCode == loc.code,
                      textCol: textCol,
                      subTextCol: subTextCol,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await sheetCtx.setLocale(loc.code);
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }



  static void _showBillingModal(BuildContext context, AppState state) {
    final isPro = state.profile?.plan == 'hazak';
    // [Punto 35 aviso] Billing debe respetar el tema. Antes siempre era fondo
    // negro cálido (#0E0C0A) con texto blanco hardcoded → "se ve marrón" en light
    // y desentonaba con el resto de la UI. Ahora detecta isLight y usa la
    // paleta coherente con el resto de la app (gris dark / yeso light).
    // [Punto 35 round 2] El usuario reportó "color marrón" en Billing → era la
    // card interna (ExodoColors.surface = #1A1612). Ahora la card usa el
    // mismo `bgColor` del modal + un borde sutil, sin marrón.
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bgColor = isLight ? Colors.white : ExodoColors.background;
    final cardBg = isLight ? ExodoColors.textPrimary : ExodoColors.composerBg;
    final borderColor = isLight ? const Color(0xFFE8E0D8) : Colors.transparent;
    final textPrimary = isLight ? const Color(0xFF191919) : ExodoColors.textPrimary;
    final textSecondary = isLight ? const Color(0xFF191919) : ExodoColors.textPrimary;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppI18n.of(context).t('settings.billing'), style: TextStyle(fontFamily: 'Syne', fontSize: 20, fontWeight: FontWeight.bold, color: textPrimary)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            AppI18n.of(context).t('billing.current_plan'),
                            style: GoogleFonts.inter(
                              color: textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isPro
                              ? AppI18n.of(context).t('billing.plan_pro')
                              : AppI18n.of(context).t('billing.plan_free'),
                          style: GoogleFonts.inter(
                            color: ExodoColors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            AppI18n.of(context).t('billing.gateway'),
                            style: GoogleFonts.inter(
                              color: textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isPro
                              ? 'Stripe / Mobile Pay'
                              : AppI18n.of(context).t('billing.gateway_free'),
                          style: GoogleFonts.inter(color: textPrimary),
                          textAlign: TextAlign.end,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (isPro)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFE57373)), padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () {
                      state.cancelProPlan();
                      Navigator.pop(ctx);
                    },
                    child: Text(AppI18n.of(context).t('billing.cancel_btn'), style: GoogleFonts.inter(color: const Color(0xFFE57373), fontWeight: FontWeight.bold)),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: ExodoColors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(AppI18n.of(context).t('billing.upgrade_btn'), style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
