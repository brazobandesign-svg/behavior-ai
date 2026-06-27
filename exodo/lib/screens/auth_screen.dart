import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/supabase_service.dart';
import '../services/app_state.dart';
import '../theme/exodo_theme.dart';

bool _isAuthEn(BuildContext context) {
  try {
    if (ui.PlatformDispatcher.instance.locale.languageCode == 'en') return true;
  } catch (_) {}
  return Localizations.localeOf(context).languageCode == 'en';
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool isLoading = false;
  bool showEmailForm = false;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final isEn = _isAuthEn(context);

    if (email.isEmpty || pass.isEmpty || (!isLogin && name.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEn ? 'Please fill all fields' : 'Por favor llena todos los campos')));
      return;
    }

    setState(() => isLoading = true);

    try {
      if (isLogin) {
        await SupabaseService.signIn(email, pass);
      } else {
        final res = await SupabaseService.signUp(email, pass, name);
        if (res.session == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: ExodoColors.amber,
                content: Text(
                  isEn
                      ? '📬 Account created. Check your email for confirmation if required.'
                      : '📬 Cuenta creada. Si Supabase pide confirmación, revisa tu correo. Si no, ya puedes iniciar sesión.',
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

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
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error Google: $e')));
                            } finally {
                              if (mounted) setState(() => isLoading = false);
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
                          _isAuthEn(context) ? 'Continue with Google' : 'Continuar con Google',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.2),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 2. Apple (Desactivado temporalmente)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF161412),
                      disabledBackgroundColor: const Color(0xFF161412).withOpacity(0.5),
                      disabledForegroundColor: Colors.white38,
                      elevation: 0,
                      side: BorderSide(color: const Color(0xFF2E2923).withOpacity(0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.apple, size: 28, color: Colors.white38),
                        const SizedBox(width: 14),
                        Text(
                          _isAuthEn(context) ? 'Continue with Apple' : 'Continuar con Apple',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.2),
                        ),
                      ],
                    ),
                  ),
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
                          _isAuthEn(context) ? 'Continue as Guest' : 'Entrar como Invitado',
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

class _TabBtn extends StatelessWidget {
  final String title;
  final bool active;
  final VoidCallback onTap;

  const _TabBtn({required this.title, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              color: active ? ExodoColors.amber : ExodoColors.textSecondary,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 40,
            height: 2,
            color: active ? ExodoColors.amber : Colors.transparent,
          ),
        ],
      ),
    );
  }
}


