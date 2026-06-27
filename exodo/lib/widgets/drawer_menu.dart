import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/supabase_service.dart';
import '../theme/exodo_theme.dart';

bool _isDrawerEn(BuildContext context) {
  try {
    if (ui.PlatformDispatcher.instance.locale.languageCode == 'en') return true;
  } catch (_) {}
  return Localizations.localeOf(context).languageCode == 'en';
}

class DrawerMenu extends StatefulWidget {
  const DrawerMenu({super.key});

  @override
  State<DrawerMenu> createState() => _DrawerMenuState();
}

class _DrawerMenuState extends State<DrawerMenu> {
  static final Set<String> _starredIds = {};
  Set<String> _matchingIds = {};
  String _searchQuery = '';
  bool _isSearching = false;
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
    final bg = isLight ? const Color(0xFFF7F5F0) : const Color(0xFF161412);
    final textCol = isLight ? const Color(0xFF171615) : ExodoColors.textPrimary;
    final subTextCol = isLight ? Colors.black54 : ExodoColors.textSecondary;

    final filtered = state.conversations.where((c) {
      if (_searchQuery.isEmpty) return true;
      return c.title.toLowerCase().contains(_searchQuery.toLowerCase()) || _matchingIds.contains(c.id);
    }).toList();

    final starredConvs = filtered.where((c) => _starredIds.contains(c.id)).toList();
    final recentConvs = filtered.where((c) => !_starredIds.contains(c.id)).toList();

    return Drawer(
      backgroundColor: bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Arriba: Exodo
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Exodo',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: textCol,
                      letterSpacing: -0.5,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: subTextCol, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 2. Opciones de menú al descubierto en color normal
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(Icons.chat_bubble_outline_rounded, size: 20, color: textCol),
              title: Text('New chat', style: GoogleFonts.inter(fontSize: 14, color: textCol, fontWeight: FontWeight.w500)),
              onTap: () {
                state.startNewChat();
                Navigator.pop(context);
              },
            ),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(state.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 20, color: textCol),
              title: Text(state.isDarkMode ? 'Light mode' : 'Dark mode', style: GoogleFonts.inter(fontSize: 14, color: textCol, fontWeight: FontWeight.w500)),
              onTap: () => state.toggleTheme(),
            ),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Image.asset(
                'assets/images/incognito-svgrepo-com.png',
                width: 20,
                height: 20,
                color: state.isIncognito ? ExodoColors.amber : textCol,
              ),
              title: Text(_isDrawerEn(context) ? 'Incognito mode' : 'Modo Incógnito', style: GoogleFonts.inter(fontSize: 14, color: state.isIncognito ? ExodoColors.amber : textCol, fontWeight: FontWeight.w500)),
              onTap: () {
                HapticFeedback.vibrate();
                state.toggleIncognito();
              },
            ),

            // 3. Buscar conversación
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: _isSearching
                  ? Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isLight ? Colors.white : const Color(0xFF1E1C19),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 18, color: subTextCol),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              autofocus: true,
                              cursorColor: textCol,
                              style: TextStyle(fontSize: 13, color: textCol),
                              decoration: InputDecoration(
                                hintText: _isDrawerEn(context) ? 'Search chats...' : 'Buscar chat...',
                                hintStyle: TextStyle(fontSize: 13, color: subTextCol),
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
                            child: Icon(Icons.close, size: 16, color: subTextCol),
                          ),
                        ],
                      ),
                    )
                  : ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Icon(Icons.search_rounded, size: 20, color: textCol),
                      title: Text(_isDrawerEn(context) ? 'Search chats' : 'Buscar conversación', style: GoogleFonts.inter(fontSize: 14, color: textCol, fontWeight: FontWeight.w500)),
                      onTap: () => setState(() => _isSearching = true),
                    ),
            ),

            const SizedBox(height: 6),
            Divider(color: isLight ? const Color(0xFFE2DDD2) : const Color(0xFF2A2622), height: 1),
            const SizedBox(height: 8),

            // 4. Historial (Starred & Recents)
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        state.conversations.isEmpty
                            ? (_isDrawerEn(context) ? 'No chat history' : 'Sin historial de chats')
                            : (_isDrawerEn(context) ? 'No chats found' : 'No se encontraron chats'),
                        style: GoogleFonts.inter(fontSize: 12.5, color: subTextCol),
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        if (starredConvs.isNotEmpty) ...[
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 6, 16, 4),
                            sliver: SliverToBoxAdapter(
                              child: Text('Starred', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: subTextCol)),
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildConvItem(starredConvs[index], state, isLight, true),
                              childCount: starredConvs.length,
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 10)),
                        ],

                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 16, 4),
                          sliver: SliverToBoxAdapter(
                            child: Text('Recents', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: subTextCol)),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildConvItem(recentConvs[index], state, isLight, false),
                            childCount: recentConvs.length,
                          ),
                        ),
                      ],
                    ),
            ),

            Divider(color: isLight ? const Color(0xFFE2DDD2) : const Color(0xFF2A2622), height: 1),

            // 5. Al fondo: SIN engranaje, solo avatar de perfil que abre modal
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _ClaudeAccountModal.show(context, state),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: ExodoColors.amber,
                          child: Text(
                            state.profile?.fullName?.isNotEmpty == true
                                ? state.profile!.fullName!.substring(0, 1).toUpperCase()
                                : 'U',
                            style: GoogleFonts.syne(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          state.profile?.fullName ?? (_isDrawerEn(context) ? 'Exodo User' : 'Usuario Éxodo'),
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: textCol),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConvItem(Conversation conv, AppState state, bool isLight, bool isStarred) {
    final active = state.activeConversation?.id == conv.id;
    final textCol = isLight ? const Color(0xFF171615) : ExodoColors.textPrimary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: active ? (isLight ? const Color(0xFFEBE7DE) : const Color(0xFF262320)) : Colors.transparent,
        onTap: () {
          state.selectConversation(conv);
          Navigator.pop(context);
        },
        onLongPress: () {
          HapticFeedback.vibrate();
          _showChatContextMenu(context, conv, state, isStarred);
        },
        title: Text(
          conv.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? (isLight ? Colors.black : Colors.white) : (isLight ? const Color(0xFF171615) : Colors.white),
          ),
        ),
        trailing: isStarred
            ? Icon(Icons.push_pin_rounded, size: 14, color: isLight ? Colors.black54 : Colors.white70)
            : null,
      ),
    );
  }

  void _showChatContextMenu(BuildContext context, Conversation conv, AppState state, bool isStarred) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isEn = _isDrawerEn(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: isLight ? Colors.white : const Color(0xFF1E1C19),
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
              title: Text(isEn ? 'Rename' : 'Renombrar', style: GoogleFonts.inter(fontSize: 15, color: isLight ? Colors.black : Colors.white, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, conv, state);
              },
            ),
            ListTile(
              leading: Icon(isStarred ? Icons.push_pin : Icons.push_pin_outlined, color: isLight ? Colors.black87 : Colors.white),
              title: Text(isEn ? (isStarred ? 'Unpin' : 'Pin') : (isStarred ? 'Desfijar' : 'Fijar'), style: GoogleFonts.inter(fontSize: 15, color: isLight ? Colors.black : Colors.white, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  if (isStarred) {
                    _starredIds.remove(conv.id);
                  } else {
                    _starredIds.add(conv.id);
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(isEn ? 'Delete' : 'Borrar', style: GoogleFonts.inter(fontSize: 15, color: Colors.redAccent, fontWeight: FontWeight.w500)),
              onTap: () async {
                Navigator.pop(ctx);
                await SupabaseService.deleteConversation(conv.id);
                state.conversations.removeWhere((c) => c.id == conv.id);
                if (state.activeConversation?.id == conv.id) state.startNewChat();
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
    final isEn = _isDrawerEn(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isLight ? Colors.white : const Color(0xFF1E1C19),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isEn ? 'Rename chat' : 'Renombrar chat', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: isLight ? Colors.black : Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: isLight ? Colors.black : Colors.white),
          decoration: InputDecoration(
            hintText: isEn ? 'Conversation title' : 'Título de la conversación',
            hintStyle: TextStyle(color: isLight ? Colors.black38 : Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isLight ? Colors.black26 : Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: isLight ? Colors.black : Colors.white)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isEn ? 'Cancel' : 'Cancelar', style: TextStyle(color: isLight ? Colors.black54 : Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final newTitle = ctrl.text.trim();
              if (newTitle.isNotEmpty) {
                state.renameConversation(conv.id, newTitle);
              }
              Navigator.pop(ctx);
            },
            child: Text(isEn ? 'Save' : 'Guardar', style: TextStyle(color: isLight ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// Modal estilo Claude Settings (fotos adjuntas)
class _ClaudeAccountModal {
  static void show(BuildContext context, AppState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1A17),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
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
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Center(
                child: Text('Settings', style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              const SizedBox(height: 20),

              // Tarjeta superior: Correo + Etiqueta Free/Pro (sin "Want more Claude")
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF282521),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        state.userEmail,
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        state.profile?.plan == 'hazak' ? 'Pro' : 'Free',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Opciones de lista con diseño limpio
              _buildSettingTile(
                icon: Icons.person_outline_rounded,
                title: 'Profile',
                onTap: () {
                  Navigator.pop(ctx);
                  _showProfileEditDialog(context, state);
                },
              ),
              const SizedBox(height: 8),
              _buildSettingTile(
                icon: Icons.monetization_on_outlined,
                title: 'Billing',
                onTap: () {
                  Navigator.pop(ctx);
                  _showBillingModal(context, state);
                },
              ),
              const SizedBox(height: 8),
              _buildSettingTile(
                icon: Icons.privacy_tip_outlined,
                title: _isDrawerEn(context) ? 'Terms & Privacy' : 'Términos y Privacidad',
                onTap: () {
                  Navigator.pop(ctx);
                  final isEn = _isDrawerEn(context);
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF282521),
                      title: Text(isEn ? 'Legal & Privacy' : 'Legal y Privacidad', style: GoogleFonts.syne(color: Colors.white)),
                      content: Text(isEn ? 'Exodo AI operates under strict data privacy and generative AI compliance.' : 'Éxodo AI opera bajo estricto cumplimiento de privacidad de datos e IA generativa.', style: GoogleFonts.inter(color: Colors.white70)),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(isEn ? 'Close' : 'Cerrar', style: const TextStyle(color: ExodoColors.amber)))],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),

              // Botón de Log out abajo en tono rojizo
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.logout_rounded, color: Color(0xFFE57373), size: 22),
                title: Text('Log out', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: const Color(0xFFE57373))),
                onTap: () async {
                  Navigator.pop(ctx);
                  state.selectModelOption(exodoModels[0]);
                  await SupabaseService.signOut();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildSettingTile({required IconData icon, required String title, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(color: const Color(0xFF221F1C), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500))),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  static void _showProfileEditDialog(BuildContext context, AppState state) {
    final nameCtrl = TextEditingController(text: state.profile?.fullName ?? '');
    final isEn = _isDrawerEn(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF221F1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isEn ? 'Edit Profile' : 'Editar Perfil', style: GoogleFonts.syne(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEn ? 'What should AI call you?' : '¿Cómo quieres que te llame la IA?', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF161412),
                hintText: isEn ? 'Your name or nickname...' : 'Tu nombre o apodo...',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(isEn ? 'Cancel' : 'Cancelar', style: const TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ExodoColors.amber, foregroundColor: Colors.black),
            onPressed: () {
              state.updateProfileName(nameCtrl.text.trim());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEn ? '✅ Name updated' : '✅ Nombre actualizado')));
            },
            child: Text(isEn ? 'Save' : 'Guardar'),
          ),
        ],
      ),
    );
  }

  static void _showBillingModal(BuildContext context, AppState state) {
    final isPro = state.profile?.plan == 'hazak';
    final isEn = _isDrawerEn(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1A17),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Billing & Plan', style: GoogleFonts.syne(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF282521), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(isEn ? 'Current plan' : 'Plan actual', style: GoogleFonts.inter(color: Colors.white60, fontSize: 13)),
                        Text(isPro ? (isEn ? '🌟 Hazak Pro (\$4.99/mo)' : '🌟 Hazak Pro (\$4.99/mes)') : (isEn ? '⚡ Genesis Free' : '⚡ Génesis Gratis'), style: GoogleFonts.inter(color: ExodoColors.amber, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(isEn ? 'Payment gateway' : 'Pasarela de pago', style: GoogleFonts.inter(color: Colors.white60, fontSize: 13)),
                        Text(isPro ? 'Stripe / Mobile Pay' : (isEn ? 'Free' : 'Gratuito'), style: GoogleFonts.inter(color: Colors.white)),
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
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEn ? 'ℹ️ Reverted to Genesis Free plan' : 'ℹ️ Has regresado al plan Génesis Gratis')));
                    },
                    child: Text(isEn ? 'Cancel subscription' : 'Cancelar suscripción', style: GoogleFonts.inter(color: const Color(0xFFE57373), fontWeight: FontWeight.bold)),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: ExodoColors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(isEn ? 'Upgrade to XPi Ehyeh Pro' : 'Mejorar a XPi Ehyeh Pro', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
