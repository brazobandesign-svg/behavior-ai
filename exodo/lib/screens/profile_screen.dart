import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../l10n/app_i18n.dart';
import '../theme/exodo_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _fullNameCtrl;
  late TextEditingController _nicknameCtrl;

  @override
  void initState() {
    super.initState();
    final state = Provider.of<AppState>(context, listen: false);
    final currentName = state.profile?.fullName ?? '';
    final currentNickname = state.profile?.onboarding?['nickname']?.toString() ?? currentName;

    _fullNameCtrl = TextEditingController(text: currentName);
    _nicknameCtrl = TextEditingController(text: currentNickname);
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _nicknameCtrl.dispose();
    super.dispose();
  }

  // [Punto 39] Modal de confirmación para borrar historial.
  // Usa la paleta Éxodo: grises, sheet, tab, yeso, hueso del dark mode.
  void _showClearHistoryConfirmation(BuildContext context, AppState state) {
    final isLight = !state.isDarkMode;
    final bg = isLight ? const Color(0xFFFBF9F5) : const Color(0xFF1E1C19);     // yeso / gris carbón
    final textCol = isLight ? const Color(0xFF171615) : ExodoColors.textPrimary;
    final subTextCol = isLight ? const Color(0xFF7B7872) : ExodoColors.textSecondary;
    final dividerColor = isLight ? const Color(0xFFD4CEBF) : ExodoColors.border;
    final cardBg = isLight ? const Color(0xFFF2ECE1) : const Color(0xFF131313);   // hueso / tab

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: ExodoColors.amber, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppI18n.of(context).t('profile.clear_history_title'),
                style: GoogleFonts.syne(color: textCol, fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Text(
          AppI18n.of(context).t('profile.clear_history_body'),
          style: GoogleFonts.inter(color: subTextCol, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppI18n.of(context).t('ctx.cancel'), style: GoogleFonts.inter(color: subTextCol, fontWeight: FontWeight.w500)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ExodoColors.amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await state.clearHistory();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: ExodoColors.amber, size: 18),
                        const SizedBox(width: 10),
                        Text('OK', style: GoogleFonts.inter(fontSize: 14, color: ExodoColors.textPrimary)),
                      ],
                    ),
                    backgroundColor: ExodoColors.surface,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Text(
              AppI18n.of(context).t('profile.clear_history_confirm'),
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, AppState state) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bgColor = isLight ? const Color(0xFFF5F2EB) : const Color(0xFF1E1E1E);
    final textCol = isLight ? const Color(0xFF171615) : Colors.white;
    final subCol = isLight ? const Color(0xFF7B7872) : Colors.white70;
    final cancelCol = isLight ? const Color(0xFF9E9689) : Colors.white54;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFE57373), size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppI18n.of(context).t('profile.delete_title'),
                style: GoogleFonts.syne(color: textCol, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          AppI18n.of(context).t('profile.delete_body'),
          style: GoogleFonts.inter(color: subCol, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppI18n.of(context).t('ctx.cancel'), style: GoogleFonts.inter(color: cancelCol, fontWeight: FontWeight.w500)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx); // Cierra modal
              Navigator.pop(context); // Cierra ProfileScreen
              await state.deleteAccount();
            },
            child: Text(AppI18n.of(context).t('profile.delete_confirm'), style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final isLight = !state.isDarkMode;
    final bg = isLight ? const Color(0xFFF7F5F0) : const Color(0xFF131313);
    final cardBg = isLight ? Colors.white : const Color(0xFF1E1E1E);
    final textCol = isLight ? const Color(0xFF171615) : Colors.white;
    final subCol = isLight ? Colors.black54 : Colors.white60;


    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textCol),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppI18n.of(context).t('settings.profile'),
          style: GoogleFonts.syne(color: textCol, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar display
                    Center(
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: ExodoColors.amber.withValues(alpha: 0.2),
                        backgroundImage: (state.userAvatarUrl != null)
                            ? NetworkImage(state.userAvatarUrl!)
                            : null,
                        child: (state.userAvatarUrl != null)
                            ? null
                            : Text(
                                state.profile?.fullName?.isNotEmpty == true
                                    ? state.profile!.fullName!.substring(0, 1).toUpperCase()
                                    : 'E',
                                style: GoogleFonts.syne(fontSize: 32, fontWeight: FontWeight.bold, color: ExodoColors.amber),
                              ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Full name label & field
                    Text(
                      AppI18n.of(context).t('profile.fullname'),
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: textCol),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _fullNameCtrl,
                      style: GoogleFonts.inter(color: textCol, fontSize: 15),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: cardBg,
                        hintText: AppI18n.of(context).t('profile.fullname_hint'),
                        hintStyle: GoogleFonts.inter(color: subCol),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // What should we call you? label & field
                    Text(
                      AppI18n.of(context).t('profile.nickname'),
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: textCol),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nicknameCtrl,
                      style: GoogleFonts.inter(color: textCol, fontSize: 15),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: cardBg,
                        hintText: AppI18n.of(context).t('profile.nickname_hint'),
                        hintStyle: GoogleFonts.inter(color: subCol),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Update profile button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ExodoColors.amber,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () async {
                          final success = await state.updateProfileDetails(_fullNameCtrl.text.trim(), _nicknameCtrl.text.trim());
                          if (!context.mounted) return;
                          if (success) {
                            Navigator.pop(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(AppI18n.of(context).t('profile.save_error')),
                                backgroundColor: const Color(0xFFE57373),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        child: Text(
                          AppI18n.of(context).t('profile.update_btn'),
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // [Punto 39] Clear History button above Delete Account.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: isLight ? const Color(0xFFD4CEBF) : ExodoColors.border),
                  ),
                  icon: Icon(Icons.delete_sweep_rounded, size: 20, color: isLight ? const Color(0xFF7B7872) : ExodoColors.textSecondary),
                  label: Text(
                    AppI18n.of(context).t('profile.clear_history_btn'),
                    style: GoogleFonts.inter(color: isLight ? const Color(0xFF7B7872) : ExodoColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  onPressed: () => _showClearHistoryConfirmation(context, state),
                ),
              ),
            ),

            // Delete Account at bottom
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFE57373)),
                  label: Text(
                    AppI18n.of(context).t('profile.delete_btn'),
                    style: GoogleFonts.inter(color: const Color(0xFFE57373), fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _showDeleteConfirmation(context, state),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
