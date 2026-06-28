import 'package:flutter/material.dart';
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error Guest: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Pantalla de login SIEMPRE en Negro Cálido (#0E0C0A), inamovible.
      backgroundColor: ExodoColors.background,
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
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error Google: $e')));
                            } finally {
                              if (context.mounted) setState(() => isLoading = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset('assets/images/google_logo.png', width: 26, height: 26),
                        const SizedBox(width: 14),
                        Text(
                          AppI18n.of(context).localeCode == 'en' ? 'Continue with Google' : 'Continuar con Google',
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppI18n.of(context).localeCode == 'en' ? 'Sign in with Apple coming soon' : 'Próximamente: Inicio de sesión con Apple',
                            style: GoogleFonts.inter(),
                          ),
                          backgroundColor: ExodoColors.amber,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF131313),
                      disabledBackgroundColor: const Color(0xFF131313).withValues(alpha: 0.5),
                      disabledForegroundColor: Colors.white38,
                      elevation: 0,
                      side: BorderSide(color: const Color(0xFF131313).withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.apple, size: 28, color: Colors.white38),
                        const SizedBox(width: 14),
                        Text(
                          AppI18n.of(context).localeCode == 'en' ? 'Continue with Apple' : 'Continuar con Apple',
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppI18n.of(context).localeCode == 'en' ? 'X / Twitter login coming soon' : 'Próximamente: Inicio de sesión con X / Twitter',
                              style: GoogleFonts.inter(),
                            ),
                            backgroundColor: ExodoColors.amber,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF131313),
                          border: Border.all(color: ExodoColors.border),
                        ),
                        child: const Center(
                          child: Text(
                            '𝕏',
                            style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Botón circular GitHub
                    InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppI18n.of(context).localeCode == 'en' ? 'GitHub login coming soon' : 'Próximamente: Inicio de sesión con GitHub',
                              style: GoogleFonts.inter(),
                            ),
                            backgroundColor: ExodoColors.amber,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF131313),
                          border: Border.all(color: ExodoColors.border),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.code,
                            color: Colors.white,
                            size: 24,
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
                    style: TextButton.styleFrom(foregroundColor: ExodoColors.textSecondary),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.privacy_tip_outlined, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          AppI18n.of(context).localeCode == 'en' ? 'Continue as Guest' : 'Entrar como Invitado',
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


