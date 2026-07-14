import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/supabase_service.dart';
import '../theme/exodo_theme.dart';
import '../l10n/app_i18n.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLoading = false;

  // Nueva función para manejar el acceso como invitado
  Future<void> _signInAsGuest() async {
    setState(() => isLoading = true);
    try {
      await SupabaseService.signInAnonymously();
    } catch (e) {
      // Error silencioso — sin SnackBar
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Pantalla de login SIEMPRE en Negro Cálido (#0E0C0A), inamovible.
      backgroundColor: ExodoColors.loginBg,
      body: SafeArea(
        child: SingleChildScrollView(
            padding: const EdgeInsets.only(left: 28, right: 28, top: 180, bottom: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      bottom: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/Logo_behavior.png',
                            height: 96,
                            color: ExodoColors.amber,
                          ),
                          Image.asset(
                            'assets/images/exodo_text.png',
                            height: 60,
                            color: ExodoColors.textPrimary,
                          ),
                          Transform.translate(
                            offset: const Offset(0, -22),
                            child: Image.asset(
                              'assets/images/bybehavior_text.png',
                              height: 40,
                              color: ExodoColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

                // 1. PRIMERA OPCIÓN: Botón oficial de Continuar con Google
                // 1. Google
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            setState(() => isLoading = true);
                            try {
                              await SupabaseService.signInWithGoogle();
                            } catch (e) {
                              // Error silencioso — sin SnackBar
                            } finally {
                              if (context.mounted) setState(() => isLoading = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ExodoColors.textPrimary,
                      foregroundColor: ExodoColors.loginBg,
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset('assets/images/google_logo.png', width: 26, height: 26),
                        const SizedBox(width: 14),
                        Text(
                          AppI18n.of(context).t('auth.continue_google'),
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.2),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 2. Apple (deshabilitado — feedback "Próximamente" para que no parezca roto)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ExodoColors.surface,
                      foregroundColor: ExodoColors.textPrimary.withValues(alpha: 0.4),
                      disabledBackgroundColor: ExodoColors.surface.withValues(alpha: 0.5),
                      disabledForegroundColor: ExodoColors.textPrimary.withValues(alpha: 0.4),
                      elevation: 0,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.apple, size: 28, color: ExodoColors.textPrimary.withValues(alpha: 0.4)),
                        const SizedBox(width: 14),
                        Text(
                          AppI18n.of(context).t('auth.continue_apple'),
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.2),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 3. Opciones sociales en círculos (X / Twitter y GitHub)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Botón circular X / Twitter
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                      },
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: ExodoColors.surface,
                        ),
                        child: const Center(
                          child: Text(
                            '𝕏',
                            style: TextStyle(fontSize: 22, color: ExodoColors.textPrimary, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Botón circular GitHub
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                      },
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: ExodoColors.surface,
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/images/github_logo.png',
                            width: 26,
                            height: 26,
                            color: ExodoColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: isLoading
                        ? null
                        : _signInAsGuest,
                    style: TextButton.styleFrom(foregroundColor: ExodoColors.textPrimary),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.privacy_tip_outlined, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          AppI18n.of(context).t('auth.continue_guest'),
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, decoration: TextDecoration.underline),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}


